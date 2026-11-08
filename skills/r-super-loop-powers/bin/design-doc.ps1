#Requires -Version 5.1
<#
  design-doc.ps1 -- the project design document (<goal-dir>/../design.md) in ONE call:
    mode -> prompt -> codex-run.ps1 -Role surveyor -> codex-status.ps1 -> shape check
    -> design.md (history row added here) -> loop-log.ps1 -Who codex-surveyor

  Modes:
    start     -GoalDir -WorkDir -Milestone <A-0|CP> [-Effort] [-WaitMinutes 9] [-Label] [-EnvFile]
              no design.md      -> create (-Effort high unless given, 30 min)
              design.md exists  -> update (15 min, role default effort unless given)
                                   or unchanged (A-0 only; nothing new since the last codex row,
                                   see Test-Unchanged): no codex, only a history row
    collect   -GoalDir -Collect <label> [-WaitMinutes 9]
    fallback  -GoalDir -WorkDir -Milestone <A-0|CP> -Fallback -Reason <text>
              (Opus writes the row after codex failed twice; body from the template if missing)

  -Milestone CP expands to "CP:<state.md milestone>". History rows are written only by this
  script: "| YYYY-MM-DD HH:MM | <goal-slug> | <tag> | <short SHA> | codex|unchanged|opus(代行: <reason>) |";
  rows codex wrote are dropped.

  stdout is KEY: VALUE lines only. STATUS OK -> LABEL / MODE / DESIGN_DOC / FEATURES /
  INSUFFICIENT / HISTORY / ELAPSED_MIN (+ WARN when design.md > 40 KB). Anything else ->
  STATUS / REASON / NEXT (a re-run command; + RAW for INCOMPLETE) and exit 1.
  Saved as UTF-8 with BOM: the headings and history cells are Japanese.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GoalDir,
    [string]$WorkDir = '',
    [string]$Milestone = '',
    [ValidateSet('', 'low', 'medium', 'high', 'xhigh', 'max')][string]$Effort = '',
    # Capped at 9 like codex-status.ps1 (one call must fit a 10-minute tool timeout).
    [int]$WaitMinutes = 9,
    [string]$Label = '',
    [string]$Collect = '',
    [switch]$Fallback,
    [string]$Reason = '',
    [string]$EnvFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'codex-common.ps1')
# Called from the Bash tool, whose console code page is not UTF-8: the milestone tag and the
# history row are Japanese (same fix as scout.ps1).
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$runScript = Join-Path $PSScriptRoot 'codex-run.ps1'
$statusScript = Join-Path $PSScriptRoot 'codex-status.ps1'
$logScript = Join-Path $PSScriptRoot 'loop-log.ps1'
$templateFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates\design-doc.md'
$RequiredSections = @('更新履歴', '構成', '機能の地図', '取り組んだが足りない', '要望はあるが未着手', '運用で見る懸念')
$SizeWarnBytes = 40960

function Stop-Failed([string]$Status, [string]$Reason, [string]$Next) {
    Write-Kv 'STATUS' $Status
    Write-Kv 'REASON' $Reason
    if ($Next) { Write-Kv 'NEXT' $Next }
    exit 1
}
function Invoke-Ps([string]$Script, [string[]]$ScriptArgs) {
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = 'powershell' }
    # A child's stderr under 2>&1 would become a terminating NativeCommandError (see scout.ps1).
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script @ScriptArgs 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $saved }
    return @{ Out = ($lines -join "`n"); Code = $code }
}
function Get-KvValue([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Key) + ': ?(.*)$')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}
# Body of "## <Name>" (optional number, trailing text tolerated) up to the next "## " heading.
# $null when the heading is absent -- that is the INCOMPLETE signal.
function Get-Section([string]$Text, [string]$Name) {
    $lf = $Text -replace "`r`n", "`n"
    $m = [regex]::Match($lf, '(?m)^##\s*(?:\d+\.?\s*)?' + [regex]::Escape($Name) + '[^\n]*\n([\s\S]*?)(?=^##\s|\z)')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}
function Get-Lines([string]$Body) {
    if ($null -eq $Body) { return @() }
    return @(($Body -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
# One line, no "|" (it would break the history table), at most $Max characters.
function Limit-Text([string]$Text, [int]$Max) {
    $s = (($Text -replace '\s+', ' ') -replace '\|', '/').Trim()
    if ($s.Length -gt $Max) { return $s.Substring(0, $Max) }
    return $s
}
function Get-DesignPath([string]$Goal) { return (Join-Path (Split-Path -Parent $Goal) 'design.md') }
# 'A-0' stays; 'CP' -> 'CP:<state.md milestone, trimmed>'. '' when it cannot be built.
function Get-MilestoneTag([string]$Ms, [string]$StateText) {
    if ($Ms -eq 'A-0') { return 'A-0' }
    if ($Ms -ne 'CP') { return '' }
    $m = [regex]::Match($StateText, '(?m)^\s*-\s*milestone:[ \t]*([^\r\n]*)')
    if (-not $m.Success) { return '' }
    $v = $m.Groups[1].Value.Trim()
    if (-not $v -or $v -eq '-') { return '' }
    return 'CP:' + $v
}
function Split-Row([string]$Line) {
    return @($Line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
}
function Test-TableFrame([string]$Line) {
    if ($Line -match '^\|[\s:|-]+\|$') { return $true }
    return ((Split-Row $Line)[0] -eq '日時')
}
# The "| ... |" lines of the 更新履歴 section, minus the header and separator rows.
function Get-HistoryRows([string]$DesignText) {
    $rows = @()
    foreach ($l in (Get-Lines (Get-Section $DesignText '更新履歴'))) {
        if ($l.StartsWith('|') -and -not (Test-TableFrame $l)) { $rows += $l }
    }
    return $rows
}
# Replace the body of the 更新履歴 section with the template's comment/header/separator lines
# plus $Rows. $null when the section is missing.
function Set-HistorySection([string]$Body, [string[]]$Rows) {
    $lf = $Body -replace "`r`n", "`n"
    $m = [regex]::Match($lf, '(?m)^##\s*(?:\d+\.?\s*)?' + [regex]::Escape('更新履歴') + '[^\n]*\n([\s\S]*?)(?=^##\s|\z)')
    if (-not $m.Success) { return $null }
    $frame = @(Get-Lines (Get-Section (Read-TextFile $templateFile) '更新履歴'))
    $g = $m.Groups[1]
    $new = "`n" + ((@($frame) + @($Rows)) -join "`n") + "`n`n"
    return $lf.Substring(0, $g.Index) + $new + $lf.Substring($g.Index + $g.Length)
}
function New-HistoryRow([string]$Tag, [string]$Sha, [string]$Writer) {
    $cells = @((Get-Date -Format 'yyyy-MM-dd HH:mm'), (Split-Path -Leaf $GoalDir), $Tag, $Sha, $Writer)
    return '| ' + (($cells | ForEach-Object { Limit-Text $_ 200 }) -join ' | ') + ' |'
}
function Get-HeadSha([string]$Dir) {
    if (-not $Dir) { return '-' }
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $s = @(& git -C $Dir rev-parse --short HEAD 2>$null)
        $code = $LASTEXITCODE
    } catch { return '-' } finally { $ErrorActionPreference = $saved }
    if ($code -ne 0 -or $s.Count -eq 0 -or -not ([string]$s[0]).Trim()) { return '-' }
    return ([string]$s[0]).Trim()
}
# Output lines of a git command in $Dir; $null when git is missing or exits non-zero.
function Get-GitLines([string]$Dir, [string[]]$GitArgs) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& git -c core.quotepath=false -C $Dir @GitArgs 2>$null | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    } catch { return $null } finally { $ErrorActionPreference = $saved }
    if ($code -ne 0) { return $null }
    return , $lines
}
# Path of $Child relative to $Parent with '/' separators; '' when it is not inside.
function Get-RelPath([string]$Parent, [string]$Child) {
    $p = $Parent.TrimEnd('\') + '\'
    if (-not ($Child.TrimEnd('\') + '\').StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { return '' }
    return $Child.Substring($p.Length).TrimEnd('\') -replace '\\', '/'
}
# Nothing to re-survey (called only for -Milestone A-0; a CP always has new retro/acceptance).
# Measured from the LATEST row written by codex (later unchanged / opus rows are skipped):
#   - committed changes since that row's SHA, ignoring that row's goal dir and design.md, and
#   - uncommitted changes, ignoring the current goal dir and design.md.
# Why those paths are ignored: Learning ends with Opus committing docs/r-super-loop-powers/, so
# HEAD always moves past the row's SHA; the previous goal's records were already ingested by its
# Learning update, so changes inside that goal's dir (and design.md itself) are not new material.
function Test-Unchanged([string]$DesignText, [string]$Work, [string]$DesignPath) {
    $base = $null
    foreach ($r in @(Get-HistoryRows $DesignText)) {
        $c = Split-Row $r
        if ($c.Count -ge 5 -and $c[4] -eq 'codex') { $base = $c }
    }
    if ($null -eq $base) { return $false }
    $sha = $base[3]
    if ($sha -notmatch '^[0-9a-f]{4,40}$') { return $false }
    $designRel = Get-RelPath $Work $DesignPath
    $docsRel = Get-RelPath $Work (Split-Path -Parent $GoalDir)
    $rowGoalRel = $(if ($docsRel) { "$docsRel/$($base[1])" } else { '' })
    $goalRel = Get-RelPath $Work $GoalDir

    $committed = Get-GitLines $Work @('diff', '--name-only', "$sha..HEAD")
    if ($null -eq $committed) { return $false }
    foreach ($path in $committed) {
        $p = $path.Trim().Trim('"')
        if (-not $p) { continue }
        if ($rowGoalRel -and $p.StartsWith($rowGoalRel + '/', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($designRel -and $p -ieq $designRel) { continue }
        return $false
    }

    $st = Get-GitLines $Work @('status', '--porcelain', '--untracked-files=all')
    if ($null -eq $st) { return $false }
    foreach ($l in $st) {
        if ($l.Length -lt 4) { continue }
        $path = $l.Substring(3)
        $arrow = $path.IndexOf(' -> ')
        if ($arrow -ge 0) { $path = $path.Substring($arrow + 4) }
        $path = $path.Trim().Trim('"')
        if ($goalRel -and $path.StartsWith($goalRel + '/', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($designRel -and $path -ieq $designRel) { continue }
        return $false
    }
    return $true
}
function Get-LowerEffort([string]$E) {
    switch ($E) {
        'max' { return 'xhigh' }
        'xhigh' { return 'high' }
        'high' { return 'medium' }
        'low' { return 'low' }
        default { return 'low' }   # medium, or the role default (medium)
    }
}
# A body wrapped whole in one ``` / ```markdown fence loses the outer fence.
function Unwrap-Fence([string]$Body) {
    $lines = @((($Body -replace "`r`n", "`n").Trim()) -split "`n")
    if ($lines.Count -ge 2 -and $lines[0] -match '^```[A-Za-z]*\s*$' -and $lines[$lines.Count - 1] -match '^```\s*$') {
        if ($lines.Count -eq 2) { return '' }
        return ($lines[1..($lines.Count - 2)] -join "`n")
    }
    return ($Body -replace "`r`n", "`n")
}
# FEATURES: body rows of the first table in 機能の地図. INSUFFICIENT: "### " headings in 取り組んだが足りない.
function Measure-Doc([string]$Body) {
    $features = 0
    $sec = Get-Section $Body '機能の地図'
    if ($null -ne $sec) {
        $block = @(); $started = $false
        foreach ($l in ($sec -split "`n")) {
            $s = $l.Trim()
            if ($s.StartsWith('|')) { $block += $s; $started = $true }
            elseif ($started) { break }
        }
        $features = [Math]::Max(0, $block.Count - 2)
    }
    $ins = 0
    $sec2 = Get-Section $Body '取り組んだが足りない'
    if ($null -ne $sec2) { $ins = [regex]::Matches($sec2, '(?m)^###\s').Count }
    return @{ Features = $features; Insufficient = $ins }
}
function Get-StartCommand([string]$Work, [string]$Tag, [string]$Eff) {
    $ms = '<A-0|CP>'
    if ($Tag -eq 'A-0') { $ms = 'A-0' } elseif ($Tag.StartsWith('CP:')) { $ms = 'CP' }
    $cmd = "design-doc.ps1 -GoalDir '$GoalDir' -WorkDir '$Work' -Milestone $ms"
    if ($Eff) { $cmd += " -Effort $Eff" }
    return $cmd
}
function Add-Log([string]$Purpose) {
    $lg = Invoke-Ps $logScript @('-GoalDir', $GoalDir, '-Who', 'codex-surveyor', '-Purpose', (Limit-Text $Purpose 300))
    if ($lg.Code -ne 0) { Write-Kv 'WARN' ('call-log not written: ' + (Get-KvValue $lg.Out 'REASON')) }
}
function Save-Design([string]$Path, [string]$Text) {
    $d = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    if (-not $Text.EndsWith("`n")) { $Text += "`n" }
    Write-TextFile $Path $Text
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetByteCount($Text)
    if ($bytes -gt $SizeWarnBytes) { Write-Kv 'WARN' ("design.md is {0} KB (> 40 KB)" -f [Math]::Ceiling($bytes / 1024.0)) }
}
function Write-Success([string]$Mode, [string]$Path, [string]$Text, [string]$Row) {
    $mm = Measure-Doc $Text
    Write-Kv 'STATUS' 'OK'
    Write-Kv 'MODE' $Mode
    Write-Kv 'DESIGN_DOC' $Path
    Write-Kv 'FEATURES' $mm.Features
    Write-Kv 'INSUFFICIENT' $mm.Insufficient
    Write-Kv 'HISTORY' $Row
}
# Template body with every section replaced by one "(未作成 ...)" line; the history frame kept,
# placeholder headings ("### <機能>") dropped.
function New-FallbackDoc([string]$Tpl, [string]$Why, [string]$Project) {
    $lines = @(($Tpl -replace "`r`n", "`n") -split "`n")
    $out = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line -match '^#{2,3}\s') {
            $j = $i + 1
            $body = @()
            while ($j -lt $lines.Count -and $lines[$j] -notmatch '^#{1,3}\s') { $body += $lines[$j]; $j++ }
            if ($line -match '^##\s*(?:\d+\.?\s*)?更新履歴') {
                $out.Add($line); foreach ($b in $body) { $out.Add($b) }
            } elseif ($line -notmatch '<[^>]*>') {
                $out.Add($line); $out.Add('')
                if (($body -join '').Trim()) { $out.Add("(未作成: Codex 失敗のため — $Why)"); $out.Add('') }
            }
            $i = $j
            continue
        }
        $out.Add($line.Replace('<プロジェクト名>', $Project))
        $i++
    }
    return ($out -join "`n")
}

if (-not (Test-Path -LiteralPath $GoalDir -PathType Container)) { Stop-Failed 'FAILED' "GoalDir does not exist: $GoalDir" '' }
$GoalDir = (Resolve-Path -LiteralPath $GoalDir).Path
$runDir = Join-Path $GoalDir 'codex-runs'
$designPath = Get-DesignPath $GoalDir
if ($WaitMinutes -gt 9) { $WaitMinutes = 9 }
if ($WaitMinutes -lt 0) { $WaitMinutes = 0 }
if (-not (Test-Path -LiteralPath $templateFile)) { Stop-Failed 'FAILED' "template not found: $templateFile" 'reinstall the plugin' }

# ---------------------------------------------------------------------------
# collect: wait, verify the shape, save with the history row, log
# ---------------------------------------------------------------------------
function Complete-Run([string]$L) {
    $metaFile = Join-Path $runDir "$L.meta.json"
    if (-not (Test-Path -LiteralPath $metaFile)) { Stop-Failed 'FAILED' "no run named '$L' in $runDir" '' }
    $meta = Read-TextFile $metaFile | ConvertFrom-Json
    $names = $meta.PSObject.Properties.Name
    $work = $(if ($names -contains 'workDir') { [string]$meta.workDir } else { '' })
    $runEffort = $(if ($names -contains 'effort') { [string]$meta.effort } else { '' })
    # The tag comes from the prompt this script wrote; a hand-launched run has none.
    $tag = '(不明)'
    $tm = [regex]::Match((Read-TextFile (Join-Path $runDir "$L.prompt.md")), '(?m)^## 節目:[ \t]*([^\r\n]+?)[ \t]*$')
    if ($tm.Success) { $tag = $tm.Groups[1].Value }

    $st = Invoke-Ps $statusScript @('-RunDir', $runDir, '-Label', $L, '-WaitMinutes', $WaitMinutes)
    $status = Get-KvValue $st.Out 'STATUS'
    if ($status -ne 'OK') {
        if (-not $status) { $status = 'FAILED' }
        $next = Get-KvValue $st.Out 'NEXT'
        if ($status -eq 'RUNNING' -or $status -eq 'STALLED') { $next = "design-doc.ps1 -GoalDir '$GoalDir' -Collect $L" }
        elseif ($status -eq 'TIMEOUT') { $next = Get-StartCommand $work $tag (Get-LowerEffort $runEffort) }
        elseif (@('FAILED', 'SUSPECT', 'LOST', 'INCOMPLETE') -contains $status) { $next = Get-StartCommand $work $tag '' }
        foreach ($k in @('REASON', 'ERROR', 'STDERR_TAIL')) { $v = Get-KvValue $st.Out $k; if ($v) { Write-Kv $k $v } }
        Write-Kv 'LABEL' $L
        Write-Kv 'STATUS' $status
        Write-Kv 'NEXT' $next
        exit 1
    }
    foreach ($w in [regex]::Matches($st.Out, '(?m)^(WARN|BOUNDARY_HIT): .*$')) { Write-Output $w.Value }

    $body = Unwrap-Fence (Read-TextFile (Join-Path $runDir "$L.last.txt"))
    $missing = @()
    foreach ($n in $RequiredSections) { if ($null -eq (Get-Section $body $n)) { $missing += $n } }
    if ($missing.Count -gt 0) {
        $raw = Join-Path $runDir "$L.raw.md"
        Write-TextFile $raw $body
        Write-Kv 'LABEL' $L
        Write-Kv 'RAW' $raw
        Stop-Failed 'INCOMPLETE' ('missing section: ' + ($missing -join ', ')) (Get-StartCommand $work $tag '')
    }

    $mode = 'create'
    $prevRows = @()
    if (Test-Path -LiteralPath $designPath) {
        $mode = 'update'
        Copy-Item -LiteralPath $designPath -Destination (Join-Path $runDir "$L.design-prev.md") -Force
        $prevRows = @(Get-HistoryRows (Read-TextFile $designPath))
    }
    $row = New-HistoryRow $tag (Get-HeadSha $work) 'codex'
    $text = Set-HistorySection $body (@($prevRows) + @($row))
    Save-Design $designPath $text
    Add-Log "${tag}: $mode"

    $elapsed = ''
    try {
        $done = Read-TextFile (Join-Path $runDir "$L.done.json") | ConvertFrom-Json
        if ($done.PSObject.Properties.Name -contains 'durationSec') { $elapsed = [string][Math]::Round([double]$done.durationSec / 60.0, 1) }
    } catch { }
    if (-not $elapsed) {
        try { $elapsed = [string][Math]::Round(((Get-Date) - [datetime]$meta.startedAt).TotalMinutes, 1) } catch { $elapsed = '0' }
    }
    Write-Kv 'LABEL' $L
    Write-Success $mode $designPath $text $row
    Write-Kv 'ELAPSED_MIN' $elapsed
    exit 0
}
if ($Collect) { Complete-Run $Collect }

# ---------------------------------------------------------------------------
# start / fallback
# ---------------------------------------------------------------------------
if (-not $WorkDir) { Stop-Failed 'FAILED' '-WorkDir is required (or pass -Collect <label>)' '' }
if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { Stop-Failed 'FAILED' "WorkDir does not exist: $WorkDir" '' }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
if ($Milestone -ne 'A-0' -and $Milestone -ne 'CP') { Stop-Failed 'FAILED' "-Milestone must be A-0 or CP (got: '$Milestone')" '' }
$tag = Get-MilestoneTag $Milestone (Read-TextFile (Join-Path $GoalDir 'state.md'))
if (-not $tag) { Stop-Failed 'FAILED' "-Milestone CP needs a 'milestone:' value in $(Join-Path $GoalDir 'state.md')" '' }
$exists = Test-Path -LiteralPath $designPath
$designText = $(if ($exists) { Read-TextFile $designPath } else { '' })

if ($Fallback) {
    $why = Limit-Text $Reason 200
    if (-not $why) { Stop-Failed 'FAILED' '-Fallback needs -Reason "<why codex failed>"' '' }
    $row = New-HistoryRow $tag (Get-HeadSha $WorkDir) "opus(代行: $why)"
    if ($exists) {
        $text = Set-HistorySection $designText (@(Get-HistoryRows $designText) + @($row))
        if ($null -eq $text) {
            $frame = @(Get-Lines (Get-Section (Read-TextFile $templateFile) '更新履歴'))
            $text = ($designText -replace "`r`n", "`n").TrimEnd() + "`n`n## 更新履歴`n`n" + ((@($frame) + @($row)) -join "`n") + "`n"
        }
    } else {
        $text = Set-HistorySection (New-FallbackDoc (Read-TextFile $templateFile) $why (Split-Path -Leaf $WorkDir)) @($row)
    }
    Save-Design $designPath $text
    Add-Log "${tag}: FAILED→Opus が代行"
    Write-Success 'fallback' $designPath $text $row
    exit 0
}

if ($exists -and $Milestone -eq 'A-0' -and (Test-Unchanged $designText $WorkDir $designPath)) {
    $row = New-HistoryRow $tag (Get-HeadSha $WorkDir) 'unchanged'
    $text = Set-HistorySection $designText (@(Get-HistoryRows $designText) + @($row))
    Save-Design $designPath $text
    Add-Log "${tag}: unchanged"
    Write-Success 'unchanged' $designPath $text $row
    exit 0
}

if (-not $EnvFile) { $EnvFile = Join-Path $GoalDir 'codex-env.json' }
if (-not (Test-Path -LiteralPath $EnvFile)) { Stop-Failed 'FAILED' "codex-env.json not found: $EnvFile" 'run codex-preflight.ps1 first (SKILL.md startup check 6)' }
if (-not (Test-Path -LiteralPath $runDir)) { New-Item -ItemType Directory -Path $runDir -Force | Out-Null }

if (-not $Label) {
    $safe = $tag -replace '[^A-Za-z0-9._-]', '.'
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $runDir -Filter 'design-*.meta.json' -ErrorAction SilentlyContinue)) {
        if ($f.Name -match ('^design-' + [regex]::Escape($safe) + '-(\d+)\.meta\.json$')) { $v = [int]$Matches[1]; if ($v -gt $n) { $n = $v } }
    }
    $Label = "design-$safe-" + ($n + 1)
}
if ($Label -notmatch '^[A-Za-z0-9._-]+$') { Stop-Failed 'FAILED' "Label must be [A-Za-z0-9._-]+ (got: $Label)" '' }
if (Test-Path -LiteralPath (Join-Path $runDir "$Label.meta.json")) { Stop-Failed 'REFUSED' "label '$Label' already exists in $runDir" "design-doc.ps1 -GoalDir '$GoalDir' -Collect $Label  (or pass a new -Label)" }

$docsDir = Split-Path -Parent $GoalDir
$docsRel = Get-RelPath $WorkDir $docsDir
if (-not $docsRel) { $docsRel = $docsDir }
if ($exists) {
    $prevSha = ''
    foreach ($r in @(Get-HistoryRows $designText)) {
        $c = Split-Row $r
        if ($c.Count -ge 4 -and $c[3] -match '^[0-9a-f]{7,40}$') { $prevSha = $c[3] }
    }
    $read = @(
        "- 前回の設計書: $designPath(土台にする。章立てと既存の行を保ち、変わったところだけ直す)"
    )
    if ($prevSha) {
        $read += @(
            "- 前回の履歴行の SHA: $prevSha。次を自分で実行し、変わったファイルに関係する行だけ見直す(読み取り専用で実行できる)",
            "  - ``git log --oneline $prevSha..HEAD``",
            "  - ``git diff --stat $prevSha..HEAD``"
        )
    } else {
        $read += '- 前回の SHA が履歴に無い: コードと記録を全体に読み直し、前回の設計書と食い違うところを直す'
    }
    $read += @(
        "- 対象プロジェクト: $WorkDir(作業ディレクトリ。git grep / rg / 直接読む)",
        "- 今回のゴール: $GoalDir(goal-seed.md・goal-frame.md・state.md・milestones/*/acceptance.md・milestones/*/retro.md・assumptions.md・hearing-log.md の ## 結論)。A-0 のときは goal-seed.md だけなので、コードの差分が中心になる",
        "- 他のゴール: $docsDir の下の他のゴールディレクトリで、前回以降に増えた acceptance.md / retro.md / hearing-log.md の結論(並行ゴールの分)$(if ($prevSha) { "。``git log --name-only $prevSha..HEAD -- $docsRel`` と未コミットのファイルで探す" })"
    )
} else {
    $read = @(
        "- 対象プロジェクト: $WorkDir(作業ディレクトリ。git grep / rg / 直接読む)",
        '- 既存の文書を先に読む: README・`docs/*.md`・`*/DESIGN.md` など。読んだものは 0 章の「詳しい資料」に列挙し、中身は繰り返さない',
        "- ゴールの記録: $docsDir の下の全ゴールディレクトリ(*/)。各ゴールで次を読む:",
        '  - `goal-seed.md`',
        '  - `goal-frame.md`(承認基準・運用で見る懸念)',
        '  - `state.md`(phase・milestone)',
        '  - `milestones/*/acceptance.md`(判定・新たな未知・要望・スキップ)',
        '  - `milestones/*/retro.md`(発見された未知・次回変えること)',
        '  - `assumptions.md`(未検証・棄却・未対応の行)',
        '  - `hearing-log.md` の `## 結論`(やらない・後回し)',
        "- 今回のゴール: $GoalDir",
        '- 読む順: 文書 → ゴール記録 → コード(足りないところだけ)'
    )
}
$read += '- 「取り組んだが足りない」の判定材料: acceptance の REJECT 理由とスキップ、retro の発見された未知、assumptions の未検証・棄却、phase が done でないゴール(finalization のまま等)、goal-frame の運用で見る懸念'

$prompt = @(
    '== TASK: DESIGN DOC ==',
    '',
    '## 目的と読み手',
    "このプロジェクトの設計書($designPath)の全文を書く。読み手は利用者で、次の要求を出す前に「もうできているか / どの機能の拡張か / 前に試して足りなかった件か」を確かめるために読む。設計・判定・提案はせず、今あるものと記録に残っていることだけを、出典を付けて書く。",
    '',
    "## モード: $(if ($exists) { '更新' } else { '作成' })",
    '',
    "## 節目: $tag",
    '',
    '## 読む材料'
) + $read + @(
    '',
    '## 書き方の決まり',
    '- 冒頭コメント: テンプレートのまま',
    '- 更新履歴: 見出しと表の見出し行・区切り行だけ残す。行はスクリプトが足す',
    '- このプロジェクトは何か: 3 行以内',
    '- 0. 構成: 0.1 全体概要はどの機械・プロセスで何が動き、何と話すかを 1 画面で。0.2 は機能ごとに「入口 → 使うコンポーネントの順 → 出口」を 1 行。細部は既存文書を指し(「詳しい資料」に列挙)、繰り返さない',
    '- 1. 機能の地図: 1 行 1 機能。到達度は できている / 一部 / 取り組んだが足りない / 進行中 / 未着手 の 5 語。「一部」「取り組んだが足りない」は末尾に → 2 章 と書く',
    '- 2. 取り組んだが足りない: 機能ごとに ### 見出しを立て、試したこと / 足りないこと / 止まっている理由 / 出典 の 4 項目。出典はゴール名とファイル(例 long-term-memory/milestones/5-…/retro.md、assumptions.md H5)。推測には (推測) を付ける',
    '- 3. 要望はあるが未着手: 受け入れで「次回」になったもの、やらない・後回しで閉じた要求。1 行 1 件、出典付き',
    '- 4. 運用で見る懸念: goal-frame の運用で見る懸念と、未検証のまま受け入れた項目。1 行 1 件、出典付き',
    '- 章立てと見出しの文言はテンプレートのまま変えない。日本語で書く。全体で 40 KB を超えない',
    '',
    '## テンプレート',
    '',
    (Read-TextFile $templateFile).TrimEnd(),
    '',
    '## 出力',
    '- 最終メッセージが設計書の全文であり、唯一の出力。前置き・要約・説明を付けない',
    '- 更新履歴の行は書かない(表の見出し行と区切り行だけ残す。行はスクリプトが足す)',
    '- 全体をコードフェンス(```)で包まない',
    ''
)
$promptFile = Join-Path $runDir "$Label.prompt.md"
Write-TextFile $promptFile (($prompt -join "`n") -replace "`r`n", "`n")

$runArgs = @('-EnvFile', $EnvFile, '-Label', $Label, '-PromptFile', $promptFile, '-WorkDir', $WorkDir, '-RunDir', $runDir, '-Role', 'surveyor')
if ($exists) {
    $runArgs += @('-TimeoutMinutes', '15')
    if ($Effort) { $runArgs += @('-Effort', $Effort) }
} else {
    $runArgs += @('-TimeoutMinutes', '30', '-Effort', $(if ($Effort) { $Effort } else { 'high' }))
}
# Contract item 1 confines codex to the working directory; add the goal documents when they
# live outside it (same rule as scout.ps1).
$inside = ($GoalDir.TrimEnd('\') + '\').StartsWith($WorkDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
if (-not $inside) { $runArgs += @('-AddDir', $GoalDir) }
$rr = Invoke-Ps $runScript $runArgs
if ($rr.Code -ne 0 -or (Get-KvValue $rr.Out 'RUN') -ne 'STARTED') {
    # Nothing was launched: do not leave an orphan prompt behind.
    Remove-Item -LiteralPath $promptFile -Force -ErrorAction SilentlyContinue
    Write-Kv 'LABEL' $Label
    Stop-Failed 'FAILED' ('codex-run.ps1 did not start the run: ' + (Limit-Text $rr.Out 400)) 'fix the cause (references/codex-invocation.md) and re-run'
}
foreach ($w in [regex]::Matches($rr.Out, '(?m)^WARN: .*$')) { Write-Output $w.Value }
Complete-Run $Label
