#Requires -Version 5.1
<#
  scout.ps1 -- one codex "scout" (read-only investigation) in ONE call:
    prompt -> codex-run.ps1 -Role scout -> codex-status.ps1 -> format check
    -> <goal-dir>/scout/<label>.md + scout/index.md -> loop-log.ps1 -Who codex-scout

  Modes:
    start    -GoalDir -WorkDir (-Question | -QuestionFile) [-Web] [-Effort] [-WaitMinutes 9]
             [-Label] [-Async] [-EnvFile]
    collect  -GoalDir -Collect <label> [-WaitMinutes 9]
    list     -GoalDir -List

  stdout is KEY: VALUE lines only. STATUS OK -> LABEL / REPORT / CONCLUSION (<= 5 lines,
  one per KV) / UNVERIFIED / WEB / ELAPSED_MIN. Anything else -> STATUS / REASON / NEXT
  (+ RAW for INCOMPLETE) and exit 1. The report file is never read back by the
  orchestrator: CONCLUSION is all it gets.
  Saved as UTF-8 with BOM: the report headings are Japanese.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GoalDir,
    [string]$WorkDir = '',
    [string]$Question = '',
    [string]$QuestionFile = '',
    [switch]$Web,
    [ValidateSet('', 'low', 'medium', 'high', 'xhigh', 'max')][string]$Effort = '',
    # Capped at 9 like codex-status.ps1 (one call must fit a 10-minute tool timeout).
    [int]$WaitMinutes = 9,
    [string]$Label = '',
    [switch]$Async,
    [string]$Collect = '',
    [switch]$List,
    [string]$EnvFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'codex-common.ps1')
# The orchestrator calls this from the Bash tool, whose console code page is not UTF-8;
# without this the Japanese CONCLUSION lines arrive garbled (smoke 2026-10-12). The
# child scripts inherit the code page, so their output round-trips as UTF-8 too.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$runScript = Join-Path $PSScriptRoot 'codex-run.ps1'
$statusScript = Join-Path $PSScriptRoot 'codex-status.ps1'
$logScript = Join-Path $PSScriptRoot 'loop-log.ps1'

function Stop-Failed([string]$Status, [string]$Reason, [string]$Next) {
    Write-Kv 'STATUS' $Status
    Write-Kv 'REASON' $Reason
    if ($Next) { Write-Kv 'NEXT' $Next }
    exit 1
}
function Invoke-Ps([string]$Script, [string[]]$ScriptArgs) {
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = 'powershell' }
    # In PowerShell 5.1 a native command's stderr under 2>&1 becomes a NativeCommandError,
    # which 'Stop' turns into a terminating error: the child's throw (stale codex-env.json,
    # for one) would then kill this script before any STATUS line. Read it as text instead.
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
function Test-CodexRunIsMine([string]$L) {
    $state = Read-TextFile (Join-Path $GoalDir 'state.md')
    return [bool]($state -match ('(?m)^\s*-\s*codex-run:\s*' + [regex]::Escape($L) + '\s*$'))
}
# -Async parks the label in state.md's codex-run:. Every terminal outcome releases it, or
# the resume packet keeps listing a finished run as an unfinished delegation.
function Clear-CodexRun([string]$L) {
    if (-not (Test-CodexRunIsMine $L)) { return }
    $lg = Invoke-Ps $logScript @('-GoalDir', $GoalDir, '-Clear', 'codex-run')
    if ($lg.Code -ne 0) { Write-Kv 'WARN' ('state.md codex-run not cleared: ' + (Get-KvValue $lg.Out 'REASON')) }
}
# Body of "## <Name>" (optional number, trailing spaces tolerated) up to the next
# "## " heading. $null when the heading is absent -- that is the INCOMPLETE signal.
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
# One line, no "|" (it would break the index columns), at most $Max characters.
function Limit-Text([string]$Text, [int]$Max) {
    $s = (($Text -replace '\s+', ' ') -replace '\|', '/').Trim()
    if ($s.Length -gt $Max) { return $s.Substring(0, $Max) }
    return $s
}

if (-not (Test-Path -LiteralPath $GoalDir -PathType Container)) { Stop-Failed 'FAILED' "GoalDir does not exist: $GoalDir" '' }
$GoalDir = (Resolve-Path -LiteralPath $GoalDir).Path
$runDir = Join-Path $GoalDir 'codex-runs'
$scoutDir = Join-Path $GoalDir 'scout'
$indexFile = Join-Path $scoutDir 'index.md'
if ($WaitMinutes -gt 9) { $WaitMinutes = 9 }
if ($WaitMinutes -lt 0) { $WaitMinutes = 0 }

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------
if ($List) {
    $idx = Read-TextFile $indexFile
    if (-not $idx.Trim()) { Write-Kv 'INDEX' 'none' } else { Write-Output $idx.TrimEnd() }
    Write-Kv 'STATUS' 'OK'
    exit 0
}

# ---------------------------------------------------------------------------
# collect: wait, verify the shape, save, index, log
# ---------------------------------------------------------------------------
function Complete-Run([string]$L) {
    if (-not (Test-Path -LiteralPath (Join-Path $runDir "$L.meta.json"))) {
        Stop-Failed 'FAILED' "no run named '$L' in $runDir" "scout.ps1 -GoalDir '$GoalDir' -List"
    }
    $st = Invoke-Ps $statusScript @('-RunDir', $runDir, '-Label', $L, '-WaitMinutes', $WaitMinutes)
    $status = Get-KvValue $st.Out 'STATUS'
    if ($status -ne 'OK') {
        if (-not $status) { $status = 'FAILED' }
        $next = Get-KvValue $st.Out 'NEXT'
        if ($status -eq 'RUNNING' -or $status -eq 'STALLED') { $next = "scout.ps1 -GoalDir '$GoalDir' -Collect $L" }
        foreach ($k in @('REASON', 'ERROR', 'STDERR_TAIL')) { $v = Get-KvValue $st.Out $k; if ($v) { Write-Kv $k $v } }
        if ($status -ne 'RUNNING' -and $status -ne 'STALLED') { Clear-CodexRun $L }
        Write-Kv 'LABEL' $L
        Write-Kv 'STATUS' $status
        Write-Kv 'NEXT' $next
        exit 1
    }
    foreach ($w in [regex]::Matches($st.Out, '(?m)^(WARN|BOUNDARY_HIT): .*$')) { Write-Output $w.Value }

    $meta = Read-TextFile (Join-Path $runDir "$L.meta.json") | ConvertFrom-Json
    $body = Read-TextFile (Join-Path $runDir "$L.last.txt")
    if (-not (Test-Path -LiteralPath $scoutDir)) { New-Item -ItemType Directory -Path $scoutDir -Force | Out-Null }
    $missing = @()
    foreach ($n in @('結論', '根拠')) { if ($null -eq (Get-Section $body $n)) { $missing += $n } }
    if ($missing.Count -gt 0) {
        $raw = Join-Path $scoutDir "$L.raw.md"
        Write-TextFile $raw $body
        Clear-CodexRun $L
        Write-Kv 'LABEL' $L
        Write-Kv 'RAW' $raw
        Stop-Failed 'INCOMPLETE' ('missing section: ' + ($missing -join ', ')) 'Re-run once with the same question; if it fails again, investigate yourself and log one codex-scout line (SKILL.md).'
    }

    # The question comes from the prompt this script wrote; a hand-launched run has none.
    $question = '(不明)'
    $promptMd = Read-TextFile (Join-Path $runDir "$L.prompt.md")
    if ($promptMd) {
        $q = Get-Section $promptMd '問い'
        if ($null -ne $q -and $q.Trim()) { $question = $q.Trim() }
    }
    $webState = 'not-requested'
    if (($meta.PSObject.Properties.Name -contains 'web') -and [bool]$meta.web) { $webState = 'used' }
    $unvLines = Get-Lines (Get-Section $body '未確認')
    if ($webState -eq 'used' -and (($unvLines -join "`n") -match 'WEB_UNAVAILABLE')) { $webState = 'unavailable' }
    $effort = ''
    if ($meta.PSObject.Properties.Name -contains 'effort') { $effort = [string]$meta.effort }
    $elapsed = ''
    try {
        $done = Read-TextFile (Join-Path $runDir "$L.done.json") | ConvertFrom-Json
        if ($done.PSObject.Properties.Name -contains 'durationSec') { $elapsed = [string][Math]::Round([double]$done.durationSec / 60.0, 1) }
    } catch { }
    if (-not $elapsed) {
        try { $elapsed = [string][Math]::Round(((Get-Date) - [datetime]$meta.startedAt).TotalMinutes, 1) } catch { $elapsed = '0' }
    }

    $now = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $report = Join-Path $scoutDir "$L.md"
    $header = "- 日時: $now`n- label: $L`n- web: $webState`n- effort: $effort`n- 問い: $(Limit-Text $question 400)`n`n"
    Write-TextFile $report ($header + $body)

    $webYn = $(if ($webState -eq 'not-requested') { 'n' } else { 'y' })
    $idx = Read-TextFile $indexFile
    if (-not $idx) { $idx = "# scout index — $(Split-Path -Leaf $GoalDir)`n`n" }
    elseif (-not $idx.EndsWith("`n")) { $idx += "`n" }
    if ($idx -notmatch ('(?m)^[^|\n]*\| ' + [regex]::Escape($L) + ' \|')) {
        Write-TextFile $indexFile ($idx + "$now | $L | web:$webYn | $(Limit-Text $question 120)`n")
    }

    $logArgs = @('-GoalDir', $GoalDir, '-Who', 'codex-scout', '-Purpose', ($L + ': ' + (Limit-Text $question 80)))
    if (Test-CodexRunIsMine $L) { $logArgs += @('-Clear', 'codex-run') }
    $lg = Invoke-Ps $logScript $logArgs
    if ($lg.Code -ne 0) { Write-Kv 'WARN' ('call-log not written: ' + (Get-KvValue $lg.Out 'REASON')) }

    Write-Kv 'STATUS' 'OK'
    Write-Kv 'LABEL' $L
    Write-Kv 'REPORT' $report
    foreach ($c in (Get-Lines (Get-Section $body '結論') | Select-Object -First 5)) { Write-Kv 'CONCLUSION' $c }
    Write-Kv 'UNVERIFIED' $unvLines.Count
    Write-Kv 'WEB' $webState
    Write-Kv 'ELAPSED_MIN' $elapsed
    exit 0
}
if ($Collect) { Complete-Run $Collect }

# ---------------------------------------------------------------------------
# start
# ---------------------------------------------------------------------------
if (-not $WorkDir) { Stop-Failed 'FAILED' '-WorkDir is required to start a scout run' '' }
if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { Stop-Failed 'FAILED' "WorkDir does not exist: $WorkDir" '' }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
if (($Question -and $QuestionFile) -or (-not $Question -and -not $QuestionFile)) { Stop-Failed 'FAILED' 'pass exactly one of -Question / -QuestionFile' '' }
if ($QuestionFile) { $Question = Read-TextFile $QuestionFile }
$Question = ($Question -replace "`r`n", "`n").Trim()
if (-not $Question) { Stop-Failed 'FAILED' 'the question is empty' '' }
if (-not $EnvFile) { $EnvFile = Join-Path $GoalDir 'codex-env.json' }
if (-not (Test-Path -LiteralPath $EnvFile)) { Stop-Failed 'FAILED' "codex-env.json not found: $EnvFile" 'run codex-preflight.ps1 first (SKILL.md startup check 6)' }
foreach ($d in @($runDir, $scoutDir)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

if (-not $Label) {
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $runDir -Filter 'scout-*.meta.json' -ErrorAction SilentlyContinue)) {
        if ($f.Name -match '^scout-(\d+)\.meta\.json$') { $v = [int]$Matches[1]; if ($v -gt $n) { $n = $v } }
    }
    $Label = 'scout-' + ($n + 1)
}
if ($Label -notmatch '^[A-Za-z0-9._-]+$') { Stop-Failed 'FAILED' "Label must be [A-Za-z0-9._-]+ (got: $Label)" '' }
if (Test-Path -LiteralPath (Join-Path $runDir "$Label.meta.json")) { Stop-Failed 'REFUSED' "label '$Label' already exists in $runDir" "scout.ps1 -GoalDir '$GoalDir' -Collect $Label  (or pass a new -Label)" }

$webLine = $(if ($Web) { '使ってよい(公式ドキュメント・一次情報を優先し、URL を根拠に書く)' } else { '使わない' })
$prompt = @(
    '== TASK: SCOUT ==',
    '## 問い',
    $Question,
    '',
    '## 調べる範囲',
    "- 対象プロジェクト: $WorkDir(作業ディレクトリ。git grep / rg / 直接読む)",
    "- ゴール文書: $GoalDir(state.md・goal-frame.md・goal-plan.md・assumptions.md・decisions.md・scout/ の過去の報告)",
    "- Web: $webLine",
    '',
    '## 報告の型(この 4 節をこの順で。最終メッセージだけが読まれる)',
    '- `## 問い` — 問いをそのまま',
    '- `## 結論` — 5 行以内。見つからなければ「見つからない」と探した場所',
    '- `## 根拠` — 主張ごとに 1 行: file:line(または URL)と引用',
    '- `## 未確認` — 確かめられなかったこと(無ければ空)',
    ''
) -join "`n"
$promptFile = Join-Path $runDir "$Label.prompt.md"
Write-TextFile $promptFile $prompt

$runArgs = @('-EnvFile', $EnvFile, '-Label', $Label, '-PromptFile', $promptFile, '-WorkDir', $WorkDir, '-RunDir', $runDir, '-Role', 'scout')
if ($Effort) { $runArgs += @('-Effort', $Effort) }
if ($Web) { $runArgs += '-Web' }
# Contract item 1 confines codex to the working directory. The goal documents normally
# live inside it (docs/r-super-loop-powers/<goal>/); when they do not, add them.
$inside = ($GoalDir.TrimEnd('\') + '\').StartsWith($WorkDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
if (-not $inside) { $runArgs += @('-AddDir', $GoalDir) }
$rr = Invoke-Ps $runScript $runArgs
if ($rr.Code -ne 0 -or (Get-KvValue $rr.Out 'RUN') -ne 'STARTED') {
    # Nothing was launched: do not leave a prompt that the resume packet would list as an
    # unfinished delegation.
    Remove-Item -LiteralPath $promptFile -Force -ErrorAction SilentlyContinue
    Write-Kv 'LABEL' $Label
    Stop-Failed 'FAILED' ('codex-run.ps1 did not start the run: ' + (Limit-Text $rr.Out 400)) 'fix the cause (references/codex-invocation.md) and re-run'
}
foreach ($w in [regex]::Matches($rr.Out, '(?m)^WARN: .*$')) { Write-Output $w.Value }

if ($Async) {
    $lg = Invoke-Ps $logScript @('-GoalDir', $GoalDir, '-SetCodexRun', $Label)
    if ($lg.Code -ne 0) { Write-Kv 'WARN' ('state.md codex-run not set: ' + (Get-KvValue $lg.Out 'REASON')) }
    Write-Kv 'STATUS' 'STARTED'
    Write-Kv 'LABEL' $Label
    Write-Kv 'NEXT' "scout.ps1 -GoalDir '$GoalDir' -Collect $Label"
    exit 0
}
Complete-Run $Label
