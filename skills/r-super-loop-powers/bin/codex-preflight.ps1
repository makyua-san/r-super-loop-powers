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
    # Builder (B-2 implementation). Recorded as codex-env.json "model".
    [string]$Model = 'gpt-6-sol',
    # Tech PM (A-2..A-4 technical assessment, read-only). Recorded as "techpmModel".
    [string]$TechPmModel = 'gpt-6-astra',
    # Human-approved interim builder (2026-09-25): used ONLY when the builder model
    # is refused as "not supported" for this account (gradual rollout). Re-probed on
    # every preflight, so the builder returns to -Model once it is available.
    # Pass '' to disable the fallback.
    [string]$BuilderFallbackModel = 'gpt-6-astra',
    [string]$MinVersion = '0.153.0',
    [int]$ProbeTimeoutSec = 300,
    [switch]$SkipModelProbe,
    [switch]$SkipWriteProbe,
    # Extra directories to name as sandbox writable roots when -s workspace-write
    # cannot construct its own (Windows "no writable root capability SIDs"). The
    # probe directory is always included; pass the project root here if delegations
    # will touch paths outside their working directory.
    [string[]]$WritableRoot = @(),
    # Directory to run the write probe in. The sandbox mints its capability SID per
    # working directory, so a fresh temp folder can fail where the real project --
    # which codex has run in before -- works. Pass the project root that delegations
    # will actually use; the probe file is deleted afterwards.
    [string]$ProbeDir = '',
    # Human-approved escalation: if -s workspace-write cannot write on this
    # machine, fall back to -s danger-full-access (codex sandbox OFF). Never set
    # this on the model's own initiative -- it is policy.md negation list item 4.
    [switch]$AllowUnsandboxed
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
foreach ($required in @('SKILL.md', 'policy.md', 'schemas\impl-report.json')) {
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

# --- 5. probes ----------------------------------------------------------------
# Runs one codex turn in a throwaway directory and reports what came back.
# $NameWritableRoots: also pass -c sandbox_workspace_write.writable_roots naming the
# throwaway probe directory plus -WritableRoot. Used for the retry after the sandbox
# fails to infer its own roots.
function Invoke-Probe([string]$Sandbox, [string]$PromptText, [bool]$NameWritableRoots = $false, [string]$Cwd = '', [string]$ProbeModel = $Model) {
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-preflight-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $cwdDir = $scratch
    if ($Cwd) { $cwdDir = (Resolve-Path -LiteralPath $Cwd).Path }
    $result = @{ dir = $scratch; cwd = $cwdDir; argLine = ''; exitCode = $null; completed = $false; text = ''; error = ''; stderr = ''; timedOut = $false }
    try {
        $promptFile = Join-Path $scratch '__prompt.txt'
        $outFile = Join-Path $scratch '__out.jsonl'
        $errFile = Join-Path $scratch '__err.txt'
        Write-TextFile $promptFile $PromptText

        $probeArgs = $inv.Prefix + @(
            'exec', '--json', '-',
            '-C', $cwdDir,
            '-s', $Sandbox,
            '-c', 'approval_policy=never',
            '-c', 'model_reasoning_effort=low',
            '--skip-git-repo-check',
            # Same as codex-run.ps1: plugin skills (superpowers) stay out of the run.
            '--disable', 'plugins'
        )
        if ($ProbeModel) { $probeArgs += @('-m', $ProbeModel) }
        if ($Sandbox -eq 'workspace-write' -and $NameWritableRoots) {
            $rootsArg = ConvertTo-WritableRootsArg (@($cwdDir) + $WritableRoot)
            if ($rootsArg) { $probeArgs += @('-c', $rootsArg) }
        }
        $result.argLine = ConvertTo-ArgLine $probeArgs

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

$ProbeFileName = 'codex-preflight-probe.txt'

# Did the probe actually put the file on disk? Cleans up the scratch directory AND
# the probe file, so a probe pointed at a real project leaves nothing behind.
function Complete-WriteProbe($Probe) {
    $f = Join-Path $Probe.cwd $ProbeFileName
    $ok = Test-Path -LiteralPath $f
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Probe.dir -Recurse -Force -ErrorAction SilentlyContinue
    return $ok
}

function Get-SandboxErrorLine($Probe) {
    if (-not $Probe) { return '' }
    $line = ($Probe.stderr -split "`r?`n" | Where-Object { $_ -match '(?i)sandbox|Rejected' } | Select-Object -Last 1)
    if ($line) { return $line.Trim() }
    return ''
}

# 5a. Does each configured model answer at all for THIS account? A model name can be
# spelled correctly and still come back as a 400 (e.g. "not supported when using
# Codex with a ChatGPT account" while a model is still rolling out).
Write-Kv 'MODEL' $Model
Write-Kv 'TECHPM_MODEL' $TechPmModel
$sandboxWriteOk = $null
$sandboxMode = 'workspace-write'
$writableRootsRequired = $false
$builderFallbackFrom = ''
if ($SkipModelProbe) {
    Write-Kv 'MODEL_PROBE' 'SKIPPED'
} else {
    # Interim fallback: only for an account-rollout refusal, never for other errors.
    if ($BuilderFallbackModel -and $BuilderFallbackModel -ne $Model) {
        $r0 = Invoke-Probe 'read-only' 'Reply with exactly: PREFLIGHT_OK'
        try {
            $ok0 = (-not $r0.timedOut) -and $r0.exitCode -eq 0 -and $r0.completed -and ($r0.text -match 'PREFLIGHT_OK')
            $refusal = "$($r0.error) $($r0.stderr)" -match 'not supported when using Codex'
            if (-not $ok0 -and $refusal) {
                Write-Kv 'MODEL_PROBE_PRIMARY' "UNAVAILABLE ($Model is not rolled out to this account)"
                $builderFallbackFrom = $Model
                $Model = $BuilderFallbackModel
                Write-Kv 'MODEL' "$Model (interim fallback)"
                Write-Kv 'WARN' "builder runs on the human-approved interim model $Model instead of $builderFallbackFrom. Record it in decisions.md; re-run preflight later to return to $builderFallbackFrom."
            }
        } finally {
            Remove-Item -LiteralPath $r0.dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $probeTargets = @(@{ key = 'MODEL_PROBE'; role = 'builder'; model = $Model })
    if ($TechPmModel -and $TechPmModel -ne $Model) {
        $probeTargets += @{ key = 'TECHPM_MODEL_PROBE'; role = 'techpm'; model = $TechPmModel }
    }
    foreach ($t in $probeTargets) {
        $r = Invoke-Probe 'read-only' 'Reply with exactly: PREFLIGHT_OK' $false '' $t.model
        try {
            if ($r.timedOut) {
                Write-Kv $t.key 'TIMEOUT'
                Add-Failure "$($t.role) model '$($t.model)' did not answer within $ProbeTimeoutSec s. codex may be hanging on stdin or the API may be stalled."
            } elseif ($r.exitCode -ne 0 -or -not $r.completed -or ($r.text -notmatch 'PREFLIGHT_OK')) {
                Write-Kv $t.key 'FAILED'
                $detail = $r.error
                if (-not $detail) { $detail = ($r.stderr -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | ' }
                Add-Failure "$($t.role) model '$($t.model)' did not answer the probe (exit=$($r.exitCode), turn.completed=$($r.completed)). $detail"
            } else {
                Write-Kv $t.key 'OK'
            }
        } finally {
            Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if ($script:Reasons.Count -gt 0) {
        Add-Failure 'Do not silently fall back to another model -- report this to the human and stop. A different model is used only when the human names it (-Model / -TechPmModel).'
        Exit-Preflight
    }
}

# 5b. Can codex actually WRITE on this machine?
    # On Windows the sandbox can fail to construct, and then every shell command is
    # rejected while the run still exits 0 with a polite final message. That is the
    # delegation that "finishes" having changed nothing. Catch it here, once, for
    # the price of one cheap turn -- not after a 40-minute milestone.
    $writePrompt = "Using a shell command, create a file named $ProbeFileName in the current directory containing WRITE_OK. Then reply with exactly: WRITE_DONE"
    if ($SkipWriteProbe) {
        Write-Kv 'SANDBOX_WRITE' 'SKIPPED'
    } else {
        # Least privilege first, and least configuration first: if plain
        # workspace-write writes here, nothing else needs to be arranged.
        $failedProbes = @()
        $w = Invoke-Probe 'workspace-write' $writePrompt
        $sandboxWriteOk = Complete-WriteProbe $w
        if (-not $sandboxWriteOk) { $failedProbes += $w }

        # Second chance BEFORE declaring the sandbox unusable: on Windows it often
        # fails only because it was left to infer its writable roots. Naming them
        # keeps least privilege; dropping the sandbox does not.
        if (-not $sandboxWriteOk) {
            $w2 = Invoke-Probe 'workspace-write' $writePrompt $true
            if (Complete-WriteProbe $w2) {
                $sandboxWriteOk = $true
                $writableRootsRequired = $true
                $w = $w2
            } else { $failedProbes += $w2 }
        }

        # Third chance: the capability SID is minted per working directory, so a
        # throwaway temp folder can fail where the project codex has run in before
        # succeeds. -ProbeDir is where the delegations will actually run.
        if (-not $sandboxWriteOk -and $ProbeDir) {
            $w3 = Invoke-Probe 'workspace-write' $writePrompt $true $ProbeDir
            if (Complete-WriteProbe $w3) {
                $sandboxWriteOk = $true
                $writableRootsRequired = $true
                $w = $w3
            } else { $failedProbes += $w3 }
        }

        if ($sandboxWriteOk) {
            $sandboxMode = 'workspace-write'
            if ($writableRootsRequired) {
                Write-Kv 'SANDBOX_WRITE' 'OK (writable_roots named explicitly)'
                Write-Kv 'WRITABLE_ROOTS_REQUIRED' 'yes'
                foreach ($r in $WritableRoot) { Write-Kv 'WRITABLE_ROOT' $r }
            } else {
                Write-Kv 'SANDBOX_WRITE' 'OK'
            }
        } else {
            Write-Kv 'SANDBOX_WRITE' 'FAILED'
            $attempt = 0
            foreach ($fp in $failedProbes) {
                $attempt++
                $detail = Get-SandboxErrorLine $fp
                if ($detail) { Write-Kv "SANDBOX_ERROR_$attempt" $detail }
                Write-Kv "SANDBOX_ATTEMPT_$attempt" $fp.argLine
            }
            $w = $failedProbes[$failedProbes.Count - 1]

            if (-not $AllowUnsandboxed) {
                Add-Failure "codex ran but could not write a file under -s workspace-write (exit=$($w.exitCode), turn.completed=$($w.completed)). Delegated implementation would silently change nothing."
                Add-Failure 'Every attempt listed above failed, including naming the writable roots explicitly.'
                if ($w.stderr -match 'writable root capability SIDs|windows sandbox') {
                    Add-Failure "This is the Windows sandbox failing to construct, not a model problem. The workaround is to run codex with its sandbox off (-AllowUnsandboxed here, -Sandbox danger-full-access at run time). That is a security decision belonging to the human (policy.md negation list item 4) -- ask before using it, and record it in assumptions.md."
                }
                Exit-Preflight
            }

            # Human-approved fallback: verify it actually works rather than assuming.
            Write-Kv 'UNSANDBOXED_APPROVED' 'yes (-AllowUnsandboxed)'
            $dProbe = Invoke-Probe 'danger-full-access' $writePrompt $false $ProbeDir
            $dOk = Complete-WriteProbe $dProbe
            if (-not $dOk) {
                Write-Kv 'SANDBOX_FALLBACK' 'FAILED'
                Add-Failure "codex could not write under -s danger-full-access either (exit=$($dProbe.exitCode), turn.completed=$($dProbe.completed)). This is no longer a sandbox problem -- report it to the human and stop."
                Exit-Preflight
            }
            $sandboxMode = 'danger-full-access'
            Write-Kv 'SANDBOX_FALLBACK' 'OK'
            Write-Kv 'WARN' "codex will run WITHOUT its sandbox (-s danger-full-access): it can run any command and touch any path, not just the workspace. Approved by the human; record it in assumptions.md and decisions.md for this goal."
        }
    }
Write-Kv 'SANDBOX_MODE' $sandboxMode

# --- 6. write codex-env.json --------------------------------------------------
# Only reached when every probe passed, so the file never describes an environment
# that cannot actually run a delegation. A failed probe exits above; the approved
# recovery is to re-run this script with -AllowUnsandboxed.
$envDir = Split-Path -Parent $EnvOut
if ($envDir -and -not (Test-Path -LiteralPath $envDir)) { New-Item -ItemType Directory -Path $envDir -Force | Out-Null }
$envObj = [ordered]@{
    kind            = $invocation.kind
    version         = $version
    model           = $Model
    techpmModel     = $TechPmModel
    builderFallbackFrom = $builderFallbackFrom
    auth            = $auth
    sandboxWriteProbe = $(if ($SkipWriteProbe) { 'SKIPPED' } else { 'RUN' })
    sandboxWriteOk  = $sandboxWriteOk
    sandbox         = $sandboxMode
    writableRootsRequired = $writableRootsRequired
    writableRoots   = @($WritableRoot)
    unsandboxed     = ($sandboxMode -eq 'danger-full-access')
    skillDir        = $skillDir
    binDir          = $PSScriptRoot
    schemaDir       = (Join-Path $skillDir 'schemas')
    resolvedAt      = (Get-Date).ToString('s')
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
