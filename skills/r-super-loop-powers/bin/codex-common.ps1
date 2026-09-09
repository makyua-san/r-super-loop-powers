#Requires -Version 5.1
# Shared helpers for the r-super-loop-powers codex helpers.
# ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI,
# so any non-ASCII literal here would silently mojibake. Japanese belongs in
# SKILL.md / references, never in these scripts.

Set-StrictMode -Version 1.0

function Write-Kv([string]$Key, $Value) { Write-Output ("{0}: {1}" -f $Key, $Value) }

# Start-Process in Windows PowerShell 5.1 joins -ArgumentList with spaces and does
# NOT quote the elements, so any path containing a space is split. Quote here.
function ConvertTo-Arg([string]$Value) {
    if ($null -eq $Value) { return '""' }
    if ($Value -eq '') { return '""' }
    if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
    return $Value
}

function ConvertTo-ArgLine([string[]]$Values) {
    return (($Values | ForEach-Object { ConvertTo-Arg $_ }) -join ' ')
}

# UTF-8 without BOM. Get-Content on a BOM'd file leaves U+FEFF on the first token,
# which breaks exit-code parsing.
function Write-TextFile([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Read-TextFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $t = [System.IO.File]::ReadAllText($Path)
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    return $t
}

# Written last and via rename, so its existence is a safe "the run is over" signal.
function Write-ExitFile([string]$Path, [string]$Text) {
    $tmp = $Path + '.tmp'
    Write-TextFile $tmp $Text
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# Start-Process -PassThru (without -Wait) hands back a Process whose ExitCode is
# unreadable later unless the handle was cached while the process was alive.
# Touch .Handle immediately after starting, or exit codes come back empty.
function Register-ProcessHandle($Process) {
    try { $null = $Process.Handle } catch { }
    return $Process
}

# Returns the exit code, or $null if it genuinely cannot be read.
function Get-ProcessExitCode($Process) {
    try { $Process.WaitForExit() } catch { }
    try {
        $code = $Process.ExitCode
        if ($null -ne $code) { return [int]$code }
    } catch { }
    return $null
}

function Test-PidAlive([int]$ProcessId) {
    if ($ProcessId -le 0) { return $false }
    try { $null = Get-Process -Id $ProcessId -ErrorAction Stop; return $true } catch { return $false }
}

# codex spawns grandchildren; /T kills the tree.
function Stop-ProcessTree([int]$ProcessId) {
    if ($ProcessId -le 0) { return }
    try { & taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null } catch { }
}

# Build the argv prefix that actually launches codex, from a codex-env.json object.
# Two shapes are supported: an npm/mise install (node + codex.js) and a native
# codex.exe. Callers never care which.
function Get-CodexInvocation($CodexEnv) {
    if ($CodexEnv.kind -eq 'node') {
        return @{ File = $CodexEnv.node; Prefix = @($CodexEnv.js) }
    }
    return @{ File = $CodexEnv.exe; Prefix = @() }
}

function Import-CodexEnv([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "codex-env.json not found: $Path  (run codex-preflight.ps1 first)"
    }
    $obj = Read-TextFile $Path | ConvertFrom-Json
    foreach ($f in @('kind', 'version', 'skillDir')) {
        if (-not ($obj.PSObject.Properties.Name -contains $f)) {
            throw "codex-env.json is missing '$f': $Path  (re-run codex-preflight.ps1)"
        }
    }
    if ($obj.kind -eq 'node') {
        if (-not (Test-Path -LiteralPath $obj.node)) { throw "node.exe no longer exists: $($obj.node)  (re-run codex-preflight.ps1)" }
        if (-not (Test-Path -LiteralPath $obj.js))   { throw "codex.js no longer exists: $($obj.js)  (re-run codex-preflight.ps1)" }
    } else {
        if (-not (Test-Path -LiteralPath $obj.exe))  { throw "codex.exe no longer exists: $($obj.exe)  (re-run codex-preflight.ps1)" }
    }
    return $obj
}
