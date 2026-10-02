#Requires -Version 5.1
# Role charter helpers shared by codex-run.ps1 and scripts/sync-roles.ps1.
# references/roles.md marks each section with "## <name> (<id>)"; a section runs
# until the next "## " heading. Both functions return '' when something is missing,
# so callers decide whether that is a warning (codex-run) or a failure (sync).

function Get-RoleSection([string]$Text, [string]$Id) {
    $lines = ($Text -replace "`r`n", "`n" -replace "`r", "`n") -split "`n"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^## .*\(' + [regex]::Escape($Id) + '\)\s*$')) { $start = $i; break }
    }
    if ($start -lt 0) { return '' }
    $end = $lines.Count
    for ($k = $start + 1; $k -lt $lines.Count; $k++) {
        if ($lines[$k] -match '^## ') { $end = $k; break }
    }
    return (($lines[$start..($end - 1)]) -join "`n").TrimEnd()
}

function Get-RoleCharter([string]$RolesFile, [string[]]$Ids) {
    if (-not $RolesFile -or -not (Test-Path -LiteralPath $RolesFile)) { return '' }
    $text = [System.IO.File]::ReadAllText($RolesFile, (New-Object System.Text.UTF8Encoding($false)))
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $parts = @()
    foreach ($id in $Ids) {
        $section = Get-RoleSection $text $id
        if (-not $section) { return '' }
        $parts += $section
    }
    return ($parts -join "`n`n")
}
