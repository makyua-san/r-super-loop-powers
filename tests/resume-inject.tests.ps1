#Requires -Version 5.1
# Tests for hooks/resume-inject.ps1 (SessionStart) and the hooks.json registration.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hook = Join-Path $root 'hooks\resume-inject.ps1'
$script:failures = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $utf8
[Console]::OutputEncoding = $utf8
function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}
function W([string]$Path, [string]$Text) {
    $d = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Get-Text([string]$Path) { if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path, $utf8) } return '' }
function Invoke-Hook([string]$Stdin) {
    $out = $Stdin | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hook 2>&1 | Out-String
    return @{ Out = $out.Trim(); Code = $LASTEXITCODE }
}
function New-Input([string]$Source, [string]$Cwd) {
    return (@{ session_id = 's'; hook_event_name = 'SessionStart'; source = $Source; cwd = $Cwd } | ConvertTo-Json -Compress)
}
function Set-Marker([string]$Goal, [datetime]$Created, [string]$Cwd = '') {
    if (-not $Cwd) { $Cwd = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Goal)) }
    W (Join-Path $Goal 'resume-pending') ("created: " + $Created.ToString('o') + "`ncwd: $Cwd`n")
}
function Get-Context($Result) {
    try { $j = $Result.Out | ConvertFrom-Json } catch { return $null }
    if (-not $j -or -not $j.hookSpecificOutput) { return $null }
    return $j.hookSpecificOutput
}

$t = Join-Path ([IO.Path]::GetTempPath()) ('rsi-' + [guid]::NewGuid().ToString('N'))
$proj = Join-Path $t 'proj'
$g1 = Join-Path $proj 'docs\r-super-loop-powers\g1'
$g2 = Join-Path $proj 'docs\r-super-loop-powers\g2'
$state = "# state — {0}`n- phase: milestone-implementation`n- 強度: MVP`n- milestone: 1-one`n- 次のCheckpoint: 1-one`n- 担当: opus-main`n- 次のゲート: impl-gate`n- 待ち: 承認待ち`n- skill-dir: C:\skill`n- codex-env: -`n- codex-run: -`n- updated: 2026-10-10 10:00`n"
W (Join-Path $g1 'state.md') ($state -f 'g1')
W (Join-Path $g1 'goal-frame.md') "## 制約`n- c`n`n## 承認基準`n1. a`n`n## 終了条件`ne`n"
W (Join-Path $g2 'state.md') ($state -f 'g2')
$m1 = Join-Path $g1 'resume-pending'
$m2 = Join-Path $g2 'resume-pending'

Set-Marker $g1 (Get-Date)
$r = Invoke-Hook (New-Input 'clear' $proj)
$ctx = Get-Context $r
Check 'clear-injects' ($r.Code -eq 0 -and $ctx -and $ctx.hookEventName -eq 'SessionStart' -and $ctx.additionalContext -match 'phase: milestone-implementation') $r.Out
Check 'clear-packet-pinned' ($ctx -and $ctx.additionalContext -match '仮説自律の否定リスト' -and $ctx.additionalContext -match '再開パケット — g1' -and $ctx.additionalContext -match '承認待ち') $r.Out
Check 'clear-marker-consumed' (-not (Test-Path -LiteralPath $m1)) 'marker still there'
Check 'clear-logged' ((Get-Text (Join-Path $g1 'hook-log.md')) -match '\| RESUME \| source=clear \| chars=\d+') (Get-Text (Join-Path $g1 'hook-log.md'))
Check 'clear-full-packet-written' (Test-Path -LiteralPath (Join-Path $g1 'resume-packet.md')) 'resume-packet.md missing'

Set-Marker $g1 (Get-Date)
$r = Invoke-Hook (New-Input 'startup' $proj)
$ctx = Get-Context $r
Check 'startup-injects' ($ctx -and $ctx.additionalContext -match '再開パケット — g1' -and -not (Test-Path -LiteralPath $m1)) $r.Out

foreach ($src in @('compact', 'resume', 'fork')) {
    Set-Marker $g1 (Get-Date)
    $r = Invoke-Hook (New-Input $src $proj)
    Check "$src-silent" ($r.Code -eq 0 -and $r.Out -eq '' -and (Test-Path -LiteralPath $m1)) $r.Out
}
Remove-Item -LiteralPath $m1 -Force

$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'no-marker-silent' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out

Set-Marker $g1 ((Get-Date).AddHours(-25))
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'stale-silent' ($r.Out -eq '') $r.Out
Check 'stale-removed' (-not (Test-Path -LiteralPath $m1)) 'stale marker kept'
Check 'stale-logged' ((Get-Text (Join-Path $g1 'hook-log.md')) -match '\| STALE \| source=clear \|') (Get-Text (Join-Path $g1 'hook-log.md'))

# A marker without "created:" falls back to its write time.
W $m1 "cwd: $proj`n"
(Get-Item -LiteralPath $m1).LastWriteTime = (Get-Date).AddHours(-30)
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'mtime-fallback-stale' ($r.Out -eq '' -and -not (Test-Path -LiteralPath $m1)) $r.Out
W $m1 "cwd: $proj`n"
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'mtime-fallback-fresh' ((Get-Context $r) -and -not (Test-Path -LiteralPath $m1)) $r.Out

# The marker's cwd must be this session's project: a marker that arrived with a clone,
# a copy or a moved checkout is discarded, never injected.
Set-Marker $g1 (Get-Date) 'C:\somewhere\else'
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'cwd-mismatch-silent' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out
Check 'cwd-mismatch-discarded' (-not (Test-Path -LiteralPath $m1)) 'marker kept'
Check 'cwd-mismatch-logged' ((Get-Text (Join-Path $g1 'hook-log.md')) -match '\| STALE \| source=clear \| cwd mismatch') (Get-Text (Join-Path $g1 'hook-log.md'))
W $m1 ("created: " + (Get-Date).ToString('o') + "`n")
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'cwd-missing-discarded' ($r.Out -eq '' -and -not (Test-Path -LiteralPath $m1)) $r.Out
# Same directory spelled differently (case, trailing separator, forward slashes) still matches.
Set-Marker $g1 (Get-Date) (($proj.ToUpperInvariant() -replace '\\', '/') + '/')
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'cwd-normalized-match' ((Get-Context $r) -and -not (Test-Path -LiteralPath $m1)) $r.Out

# Over the host's 10,000-char cap: hand the packet over uncut (Claude Code files it and
# shows a preview that starts with state.md); never cut pinned sections.
$g4 = Join-Path $proj 'docs\r-super-loop-powers\g4'
W (Join-Path $g4 'state.md') ($state -f 'g4')
W (Join-Path $g4 'goal-frame.md') ("## 制約`n" + ('制' * 12000) + "`n`n## 承認基準`n1. PINNED-CRITERION`n`n## 終了条件`nPINNED-EXIT`n")
W (Join-Path $g4 'impl-runs\m3-impl.prompt.md') 'p'
Set-Marker $g4 (Get-Date)
$r = Invoke-Hook (New-Input 'clear' $proj)
$ctx = Get-Context $r
Check 'overflow-not-cut' ($ctx -and $ctx.additionalContext.Length -gt 9500 -and $ctx.additionalContext -match 'PINNED-CRITERION' -and $ctx.additionalContext -match 'PINNED-EXIT' -and $ctx.additionalContext -match 'impl-runs/m3-impl' -and $ctx.additionalContext -match '## 9\. 直近 retro') $r.Out
Check 'overflow-logged' ((Get-Text (Join-Path $g4 'hook-log.md')) -match '\| RESUME \| source=clear \| chars=\d+ over=1') (Get-Text (Join-Path $g4 'hook-log.md'))

# Two goals: the newest marker wins, the other stays.
Set-Marker $g2 ((Get-Date).AddHours(-2))
Set-Marker $g1 (Get-Date)
$r = Invoke-Hook (New-Input 'clear' $proj)
$ctx = Get-Context $r
Check 'newest-marker-wins' ($ctx -and $ctx.additionalContext -match '再開パケット — g1' -and $ctx.additionalContext -notmatch '再開パケット — g2') $r.Out
Check 'older-marker-kept' ((Test-Path -LiteralPath $m2) -and -not (Test-Path -LiteralPath $m1)) 'markers'
Remove-Item -LiteralPath $m2 -Force

# Only the session's cwd is scanned.
$other = Join-Path $t 'other'
New-Item -ItemType Directory -Path $other -Force | Out-Null
Set-Marker $g1 (Get-Date)
$r = Invoke-Hook (New-Input 'clear' $other)
Check 'other-cwd-silent' ($r.Out -eq '' -and (Test-Path -LiteralPath $m1)) $r.Out
Remove-Item -LiteralPath $m1 -Force

# Packet cannot be built: marker renamed, ERROR logged, nothing injected.
$g3 = Join-Path $proj 'docs\r-super-loop-powers\g3'
New-Item -ItemType Directory -Path $g3 -Force | Out-Null
Set-Marker $g3 (Get-Date)
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'error-silent' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out
Check 'error-marker-renamed' ((Test-Path -LiteralPath (Join-Path $g3 'resume-pending.failed')) -and -not (Test-Path -LiteralPath (Join-Path $g3 'resume-pending'))) 'marker'
Check 'error-logged' ((Get-Text (Join-Path $g3 'hook-log.md')) -match '\| ERROR \| source=clear \|') (Get-Text (Join-Path $g3 'hook-log.md'))

$r = Invoke-Hook 'this is not json'
Check 'bad-stdin-open' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out
$r = Invoke-Hook (New-Input 'clear' (Join-Path $t 'nowhere'))
Check 'missing-cwd-silent' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out

$hj = Get-Content -Raw (Join-Path $root 'hooks\hooks.json') | ConvertFrom-Json
$ss = @($hj.hooks.SessionStart)[0]
Check 'hooks-json-sessionstart' ($ss.matcher -eq 'startup|clear' -and $ss.hooks[0].type -eq 'command' -and $ss.hooks[0].command -match 'resume-inject\.ps1' -and $ss.hooks[0].command -match 'CLAUDE_PLUGIN_ROOT' -and $ss.hooks[0].timeout -eq 30) ($ss | ConvertTo-Json -Depth 4)
$pt = @($hj.hooks.PostToolUse)[0]
Check 'hooks-json-posttooluse' ($pt.matcher -eq 'Agent' -and $pt.hooks[0].command -match 'context-meter\.ps1' -and $pt.hooks[0].command -match 'CLAUDE_PLUGIN_ROOT' -and $pt.hooks[0].timeout -eq 10) ($pt | ConvertTo-Json -Depth 4)
$stop = @($hj.hooks.Stop)[0].hooks[0]
Check 'hooks-json-stop-kept' ($stop.command -match 'human-message-check\.ps1' -and $stop.timeout -eq 90) ($stop | ConvertTo-Json)
foreach ($f in @('hooks\resume-inject.ps1', 'hooks\hook-common.ps1')) {
    $b = [IO.File]::ReadAllBytes((Join-Path $root $f))
    Check "bom-$f" ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) "save $f as UTF-8 with BOM"
}

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
