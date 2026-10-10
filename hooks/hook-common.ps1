#Requires -Version 5.1
<#
  hook-common.ps1 -- helpers shared by the r-super-loop-powers hooks
  (Stop: human-message-check, SessionStart: resume-inject, PostToolUse: context-meter).
  Dot-source it:  . (Join-Path $PSScriptRoot 'hook-common.ps1')
  Saved as UTF-8 with BOM because Find-GoalDir matches a Japanese word.
#>

$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-StdinUtf8 {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $Utf8)
    return $reader.ReadToEnd()
}

function Write-StdoutUtf8([string]$Text) {
    $bytes = $Utf8.GetBytes($Text)
    $out = [Console]::OpenStandardOutput()
    $out.Write($bytes, 0, $bytes.Length)
    $out.Flush()
}

function Write-HookJson($Object) {
    Write-StdoutUtf8 ($Object | ConvertTo-Json -Compress -Depth 4)
}

# Newest state.md whose phase is not done; $null when the loop is not active here.
# Real state files decorate the value ("- phase: **done**(2026-09-25)", "**完了(...)**"),
# so only the leading word counts ("実装完了。…待ち" is still active).
function Find-GoalDir([string]$Cwd) {
    $root = Join-Path $Cwd 'docs\r-super-loop-powers'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $states = @(Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
            Get-Item -LiteralPath (Join-Path $_.FullName 'state.md') -ErrorAction SilentlyContinue })
    $active = @($states | Where-Object {
            $_ -and ([System.IO.File]::ReadAllText($_.FullName, $Utf8) -notmatch '(?m)^\s*-\s*phase:\s*\**\s*(done\b|完了)') })
    if ($active.Count -eq 0) { return $null }
    return ($active | Sort-Object LastWriteTime | Select-Object -Last 1).DirectoryName
}

# One line per event in <goal-dir>/hook-log.md:
#   "YYYY-MM-DD HH:MM | <Result> | <Field3> | <Note>"   (the same 4 columns as v0.8)
function Write-HookLogLine([string]$GoalDir, [string]$Result, [string]$Field3, [string]$Note) {
    try {
        $one = ($Note -replace '[\r\n|]+', ' ').Trim()
        if ($one.Length -gt 200) { $one = $one.Substring(0, 200) }
        $line = '{0} | {1} | {2} | {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $Result, $Field3, $one
        [System.IO.File]::AppendAllText((Join-Path $GoalDir 'hook-log.md'), $line + "`n", $Utf8)
    } catch { }
}
