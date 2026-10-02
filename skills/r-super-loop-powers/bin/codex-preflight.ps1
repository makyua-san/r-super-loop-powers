#Requires -Version 5.1
<#
  codex-preflight.ps1 -- resolve the codex CLI and prove it can actually answer,
  once per goal. Writes codex-env.json; every later call reads that file instead of
  re-deriving paths.

  Emits "KEY: VALUE" lines. The last line is always "PREFLIGHT: OK" or
  "PREFLIGHT: FAILED" followed by "REASON: ...". Exit code 0 only on OK.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EnvOut,
    # The one codex model (tech PM / tech reviewer / graphic recorder, all read-only).
    [string]$Model = 'gpt-6.1-sol',
    [string]$MinVersion = '0.153.0',
    [int]$ProbeTimeoutSec = 300,
    [switch]$SkipModelProbe
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'codex-common.ps1')

$script:Reasons = @()
function Add-Failure([string]$Text) { $script:Reasons += $Text }

function Exit-Preflight {
    if ($script:Reasons.Count -gt 0) {
        Write-Kv 'PREFLIGHT' 'FAILED'
        foreach ($r in $script:Reasons) { Write-Kv 'REASON' $r }
        exit 1
    }
    Write-Kv 'PREFLIGHT' 'OK'
    exit 0
}

# --- 1. skill directory -------------------------------------------------------
$skillDir = Split-Path -Parent $PSScriptRoot
Write-Kv 'SKILL_DIR' $skillDir
foreach ($required in @('SKILL.md', 'policy.md', 'schemas\impl-report.json', 'bin\impl-check.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $skillDir $required))) {
        Add-Failure "skill directory is incomplete: $required not found under $skillDir"
    }
}
if ($script:Reasons.Count -gt 0) { Exit-Preflight }

# --- 2. resolve the codex entry point ----------------------------------------
# A bare `codex` is a version-manager shim on this class of machine, and a .cmd
# shim destroys multi-line arguments. Always resolve to the real thing.
$candidates = New-Object System.Collections.ArrayList
function Add-Candidate($Path) {
    if (-not $Path) { return }
    $p = ([string]$Path).Trim()
    if (-not $p) { return }
    if (-not (Test-Path -LiteralPath $p)) { return }
    $full = (Resolve-Path -LiteralPath $p).Path
    if (-not $candidates.Contains($full)) { [void]$candidates.Add($full) }
}

try { Add-Candidate (& mise which codex 2>$null | Select-Object -First 1) } catch { }
try {
    $gc = Get-Command codex -ErrorAction SilentlyContinue
    if ($gc) { Add-Candidate $gc.Source }
} catch { }
try { foreach ($line in (& where.exe codex 2>$null)) { Add-Candidate $line } } catch { }
# Native installer layout.
try {
    $nativeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    if (Test-Path -LiteralPath $nativeRoot) {
        foreach ($exe in (Get-ChildItem -Path $nativeRoot -Recurse -Filter 'codex.exe' -ErrorAction SilentlyContinue)) {
            Add-Candidate $exe.FullName
        }
    }
} catch { }

function Resolve-Invocation([string]$Path) {
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -eq '.exe') { return @{ kind = 'exe'; exe = $Path } }

    # .js, or a shim (.cmd/.bat/.ps1/extensionless) sitting next to the package.
    $js = $null
    if ($ext -eq '.js') {
        $js = $Path
    } else {
        $dir = Split-Path -Parent $Path
        for ($i = 0; $i -lt 4 -and $dir; $i++) {
            $probe = Join-Path $dir 'node_modules\@openai\codex\bin\codex.js'
            if (Test-Path -LiteralPath $probe) { $js = (Resolve-Path -LiteralPath $probe).Path; break }
            $dir = Split-Path -Parent $dir
        }
    }
    if (-not $js) { return $null }

    # Prefer the node.exe shipped with the same install, then PATH.
    $node = $null
    $dir = Split-Path -Parent $js
    for ($i = 0; $i -lt 6 -and $dir; $i++) {
        $probe = Join-Path $dir 'node.exe'
        if (Test-Path -LiteralPath $probe) { $node = (Resolve-Path -LiteralPath $probe).Path; break }
        $dir = Split-Path -Parent $dir
    }
    if (-not $node) {
        $gcNode = Get-Command node -ErrorAction SilentlyContinue
        if ($gcNode) { $node = $gcNode.Source }
    }
    if (-not $node) { return $null }
    return @{ kind = 'node'; node = $node; js = $js }
}

$invocation = $null
foreach ($c in $candidates) {
    $r = Resolve-Invocation $c
    if ($r) { $invocation = $r; break }
}
if (-not $invocation) {
    Add-Failure 'codex CLI not found. Install it (npm install -g @openai/codex) or check that codex is on PATH.'
    Exit-Preflight
}

if ($invocation.kind -eq 'node') {
    Write-Kv 'CODEX_KIND' 'node'
    Write-Kv 'CODEX_NODE' $invocation.node
    Write-Kv 'CODEX_JS' $invocation.js
} else {
    Write-Kv 'CODEX_KIND' 'exe'
    Write-Kv 'CODEX_EXE' $invocation.exe
}

# --- 3. version ---------------------------------------------------------------
$inv = Get-CodexInvocation $invocation
$verRaw = ''
try {
    $verArgs = $inv.Prefix + @('--version')
    $verRaw = (& $inv.File $verArgs 2>&1 | Out-String).Trim()
} catch {
    Add-Failure "codex --version did not run: $($_.Exception.Message)"
    Exit-Preflight
}
$verMatch = [regex]::Match($verRaw, '(\d+)\.(\d+)\.(\d+)')
if (-not $verMatch.Success) {
    Add-Failure "could not parse a version out of: $verRaw"
    Exit-Preflight
}
$version = $verMatch.Value
Write-Kv 'CODEX_VERSION' $version
if ([version]$version -lt [version]$MinVersion) {
    Add-Failure "codex $version is older than the required $MinVersion. Upgrade: npm install -g @openai/codex"
}
# Known-bad releases: the exec stdin deadlock (openai/codex#972).
if (@('0.120.0', '0.120.1', '0.120.2') -contains $version) {
    Write-Kv 'WARN' "codex $version has a known exec stdin deadlock. Upgrade before relying on delegation."
}
if ($script:Reasons.Count -gt 0) { Exit-Preflight }

# --- 4. auth ------------------------------------------------------------------
# Multi-signal on purpose: a file-only check false-negatives for env-auth users.
$codexHome = $env:CODEX_HOME
if (-not $codexHome) { $codexHome = Join-Path $env:USERPROFILE '.codex' }
$authFile = Join-Path $codexHome 'auth.json'
$auth = 'MISSING'
if ($env:CODEX_API_KEY) { $auth = 'env:CODEX_API_KEY' }
elseif ($env:OPENAI_API_KEY) { $auth = 'env:OPENAI_API_KEY' }
elseif (Test-Path -LiteralPath $authFile) { $auth = "file:$authFile" }
Write-Kv 'AUTH' $auth
if ($auth -eq 'MISSING' -and $SkipModelProbe) {
    Add-Failure 'no codex credentials found (CODEX_API_KEY / OPENAI_API_KEY / auth.json) and the model probe was skipped. Run: codex login'
    Exit-Preflight
}

# --- 5. model probe -------------------------------------------------------------
# One cheap read-only turn. A model name can be spelled correctly and still come
# back as a 400 (e.g. "not supported when using Codex with a ChatGPT account").
function Invoke-Probe([string]$PromptText) {
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-preflight-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $result = @{ dir = $scratch; exitCode = $null; completed = $false; text = ''; error = ''; stderr = ''; timedOut = $false }
    try {
        $promptFile = Join-Path $scratch '__prompt.txt'
        $outFile = Join-Path $scratch '__out.jsonl'
        $errFile = Join-Path $scratch '__err.txt'
        Write-TextFile $promptFile $PromptText
        $probeArgs = $inv.Prefix + @(
            'exec', '--json', '-',
            '-C', $scratch,
            '-s', 'read-only',
            '-c', 'approval_policy=never',
            '-c', 'model_reasoning_effort=low',
            '--skip-git-repo-check',
            '--disable', 'plugins',
            '-m', $Model
        )
        $p = Register-ProcessHandle (Start-Process -FilePath $inv.File -ArgumentList (ConvertTo-ArgLine $probeArgs) `
                -RedirectStandardInput $promptFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
                -NoNewWindow -PassThru)
        if (-not $p.WaitForExit($ProbeTimeoutSec * 1000)) {
            Stop-ProcessTree $p.Id
            $result.timedOut = $true
            return $result
        }
        $result.exitCode = Get-ProcessExitCode $p
        $result.stderr = Read-TextFile $errFile
        foreach ($line in ((Read-TextFile $outFile) -split "`r?`n")) {
            if (-not $line.Trim()) { continue }
            try { $ev = $line | ConvertFrom-Json } catch { continue }
            if ($ev.type -eq 'turn.completed') { $result.completed = $true }
            if ($ev.type -eq 'error' -and -not $result.error) { $result.error = [string]$ev.message }
            if ($ev.type -eq 'item.completed' -and $ev.item -and $ev.item.type -eq 'agent_message') {
                $result.text += [string]$ev.item.text
            }
        }
        return $result
    } catch {
        $result.error = $_.Exception.Message
        return $result
    }
}

Write-Kv 'MODEL' $Model
if ($SkipModelProbe) {
    Write-Kv 'MODEL_PROBE' 'SKIPPED'
} else {
    $r = Invoke-Probe 'Reply with exactly: PREFLIGHT_OK'
    try {
        if ($r.timedOut) {
            Write-Kv 'MODEL_PROBE' 'TIMEOUT'
            Add-Failure "model '$Model' did not answer within $ProbeTimeoutSec s. codex may be hanging on stdin or the API may be stalled."
        } elseif ($r.exitCode -ne 0 -or -not $r.completed -or ($r.text -notmatch 'PREFLIGHT_OK')) {
            Write-Kv 'MODEL_PROBE' 'FAILED'
            $detail = $r.error
            if (-not $detail) { $detail = ($r.stderr -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | ' }
            Add-Failure "model '$Model' did not answer the probe (exit=$($r.exitCode), turn.completed=$($r.completed)). $detail"
            Add-Failure 'Do not silently fall back to another model -- report this to the human and stop. A different model is used only when the human names it (-Model).'
        } else {
            Write-Kv 'MODEL_PROBE' 'OK'
        }
    } finally {
        Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:Reasons.Count -gt 0) { Exit-Preflight }
}

# --- 6. write codex-env.json --------------------------------------------------
# Only reached when every probe passed.
$envDir = Split-Path -Parent $EnvOut
if ($envDir -and -not (Test-Path -LiteralPath $envDir)) { New-Item -ItemType Directory -Path $envDir -Force | Out-Null }
$envObj = [ordered]@{
    kind       = $invocation.kind
    version    = $version
    model      = $Model
    auth       = $auth
    codexHome  = $codexHome
    skillDir   = $skillDir
    binDir     = $PSScriptRoot
    schemaDir  = (Join-Path $skillDir 'schemas')
    resolvedAt = (Get-Date).ToString('s')
}
if ($invocation.kind -eq 'node') {
    $envObj.node = $invocation.node
    $envObj.js = $invocation.js
} else {
    $envObj.exe = $invocation.exe
}
Write-TextFile $EnvOut (($envObj | ConvertTo-Json -Depth 4))
Write-Kv 'ENV_FILE' $EnvOut

Exit-Preflight
