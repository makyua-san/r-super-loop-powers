#Requires -Version 5.1
<#
  resume-packet.ps1 -- build the resume packet for one goal, deterministically.

  The packet is what the orchestrator (Opus) reads right after /clear: state.md, the
  pinned constraints (negative list, goal-frame constraints / acceptance criteria /
  exit conditions, what it is waiting for), the current milestones, the unverified
  assumptions, the latest verdict, the latest retro lessons, and delegations that
  were started but never finished. No model summarises anything here, so nothing
  can be "lost in compaction".

  Outputs:
    <goal-dir>/resume-packet.md   always: the full text, nothing cut
    -OutFile <path>               optional: the same text with the non-pinned
                                  sections cut to fit -MaxChars (Claude Code caps a
                                  hook's additionalContext at 10,000 characters)
  stdout is KV only: PACKET / FULL_CHARS / INJECT / CHARS / TRUNCATED / WARN.
  Exit 1 (throw) when state.md is missing or empty.

  Saved as UTF-8 with BOM: it matches Japanese headings.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GoalDir,
    [string]$OutFile,
    # policy.md that holds "## 仮説自律の否定リスト". Empty = this skill's policy.md.
    [string]$PolicyFile,
    [int]$MaxChars = 9500
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'codex-common.ps1')

if (-not (Test-Path -LiteralPath $GoalDir -PathType Container)) { throw "GoalDir does not exist: $GoalDir" }
$GoalDir = (Resolve-Path -LiteralPath $GoalDir).Path
if (-not $PolicyFile) { $PolicyFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'policy.md' }
$slug = Split-Path -Leaf $GoalDir
$loopRoot = Split-Path -Parent $GoalDir
$fullFile = Join-Path $GoalDir 'resume-packet.md'

# Caps (characters) for the sections that may be cut (6-9). Pinned sections (1-5) have
# none and come first, so a hard cut by the host can only reach the cuttable ones.
$Caps = @{ 6 = 2000; 7 = 2500; 8 = 1200; 9 = 1000 }
$MinCap = 200

function Get-Lines([string]$Text) { return ((($Text -replace "`r`n", "`n") -replace "`r", "`n") -split "`n") }

# "## <prefix>..." up to the next "## " heading. '' when the heading is missing.
function Get-Section([string]$Text, [string]$HeadingPrefix) {
    if (-not $Text) { return '' }
    $lines = Get-Lines $Text
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('## ' + $HeadingPrefix)) { $start = $i; break }
    }
    if ($start -lt 0) { return '' }
    $end = $lines.Count
    for ($k = $start + 1; $k -lt $lines.Count; $k++) { if ($lines[$k] -match '^## ') { $end = $k; break } }
    return (($lines[$start..($end - 1)]) -join "`n").TrimEnd()
}

function Get-StateField([string]$StateText, [string]$Key) {
    $m = [regex]::Match($StateText, '(?m)^\s*-\s*' + [regex]::Escape($Key) + ':[ \t]*([^\r\n]*)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Get-Missing([string]$File, [string]$What) { return "(見つからない: $File に「$What」が無い)" }

function Get-Newest($Files) {
    $list = @($Files | Where-Object { $_ })
    if ($list.Count -eq 0) { return $null }
    return ($list | Sort-Object LastWriteTime, FullName | Select-Object -Last 1)
}

function Get-FilesUnder([string]$Dir, [string]$Filter) {
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue)
}

function Get-RelativePath([string]$Full, [string]$Base) { return $Full.Substring($Base.Length + 1) }

# --- 1. state.md ----------------------------------------------------------------
$stateText = Read-TextFile (Join-Path $GoalDir 'state.md')
if (-not $stateText.Trim()) { throw "state.md not found or empty: $GoalDir" }
$stateBody = (($stateText -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd()
$skillDir = Get-StateField $stateText 'skill-dir'
if (-not $skillDir) { $skillDir = '(state.md に skill-dir: が無い)' }

# --- 2. waiting -----------------------------------------------------------------
$wait = Get-StateField $stateText '待ち'
if (-not $wait -or $wait -eq '-') { $wait = 'なし' }

# --- 3. negative list (policy.md, verbatim) -------------------------------------
$neg = Get-Section (Read-TextFile $PolicyFile) '仮説自律の否定リスト'
if (-not $neg) { $neg = Get-Missing $PolicyFile '## 仮説自律の否定リスト' }

# --- 4. goal-frame: constraints / acceptance criteria / exit conditions ----------
$gfText = Read-TextFile (Join-Path $GoalDir 'goal-frame.md')
$frameParts = @()
foreach ($h in @('制約', '承認基準', '終了条件')) {
    $s = Get-Section $gfText $h
    if (-not $s) { $s = Get-Missing 'goal-frame.md' "## $h" }
    $frameParts += $s
}
$frame = $frameParts -join "`n`n"

# --- 5. milestones (goal-plan.md) -----------------------------------------------
$ms = Get-Section (Read-TextFile (Join-Path $GoalDir 'goal-plan.md')) 'マイルストーン'
if (-not $ms) { $ms = Get-Missing 'goal-plan.md' '## マイルストーン' }

# --- 6. unverified assumptions --------------------------------------------------
$asText = Read-TextFile (Join-Path $GoalDir 'assumptions.md')
if ($asText) {
    $rows = @(Get-Lines $asText | Where-Object { $_.TrimStart().StartsWith('|') })
    $header = @($rows | Select-Object -First 2)
    $unverified = @($rows | Select-Object -Skip 2 | Where-Object {
            $cells = @(($_.Trim().TrimStart('|').TrimEnd('|')) -split '\|')
            $last = ''
            for ($c = $cells.Count - 1; $c -ge 0; $c--) { if ($cells[$c].Trim()) { $last = $cells[$c].Trim(); break } }
            $last.StartsWith('未検証')
        })
    if ($unverified.Count -gt 0) { $asm = (($header + $unverified) -join "`n") } else { $asm = '(未検証の仮定はない)' }
} else {
    $asm = Get-Missing 'assumptions.md' '仮定台帳'
}

# --- 7. latest verdict ----------------------------------------------------------
$decFiles = @()
$ggd = Join-Path $GoalDir 'goal-gate-decision.md'
if (Test-Path -LiteralPath $ggd) { $decFiles += Get-Item -LiteralPath $ggd }
$decFiles += Get-FilesUnder (Join-Path $GoalDir 'milestones') 'gate-decision*.md'
$dec = ''
$latestDec = Get-Newest $decFiles
if ($latestDec) {
    $head = @(Get-Lines (Read-TextFile $latestDec.FullName) | Select-Object -First 8)
    $dec = ('[' + (Get-RelativePath $latestDec.FullName $GoalDir) + ']' + "`n" + ($head -join "`n")).TrimEnd()
}
$latestEsc = Get-Newest (Get-FilesUnder (Join-Path $GoalDir 'milestones') 'escalation-*.md')
if ($latestEsc) {
    $line7 = @(Get-Lines (Read-TextFile $latestEsc.FullName) | Where-Object { $_ -match '^7\.' }) | Select-Object -First 1
    if ($line7) { $dec = ($dec + "`n`n[" + (Get-RelativePath $latestEsc.FullName $GoalDir) + ']' + "`n" + $line7).Trim() }
}
if (-not $dec) { $dec = '(判定はまだない)' }

# --- 8. latest retro of this project: what to change next time -------------------
$retro = ''
$latestRetro = Get-Newest (Get-FilesUnder $loopRoot 'retro.md')
if ($latestRetro) {
    $sec = Get-Section (Read-TextFile $latestRetro.FullName) '次回変えること'
    if ($sec) { $retro = '[' + (Get-RelativePath $latestRetro.FullName $loopRoot) + ']' + "`n" + $sec }
}
if (-not $retro) { $retro = '(retro はまだない)' }

# --- 9. unfinished delegations --------------------------------------------------
$unfinished = @()
$implDir = Join-Path $GoalDir 'impl-runs'
if (Test-Path -LiteralPath $implDir) {
    foreach ($p in @(Get-ChildItem -LiteralPath $implDir -File -Filter '*.prompt.md')) {
        $label = $p.Name.Substring(0, $p.Name.Length - 10)
        if (-not (Test-Path -LiteralPath (Join-Path $implDir "$label.report.md"))) {
            $unfinished += "impl-runs/$label (prompt あり・report なし。実装役の委譲はセッションを跨がない: git status を見てから新しいラベルで再委譲)"
        }
    }
}
$codexDir = Join-Path $GoalDir 'codex-runs'
if (Test-Path -LiteralPath $codexDir) {
    foreach ($p in @(Get-ChildItem -LiteralPath $codexDir -File -Filter '*.prompt.md')) {
        $label = $p.Name.Substring(0, $p.Name.Length - 10)
        if (-not (Test-Path -LiteralPath (Join-Path $codexDir "$label.exit"))) {
            $unfinished += "codex-runs/$label (prompt あり・exit なし。codex-status.ps1 で判定してから次を決める)"
        }
    }
}
$codexRun = Get-StateField $stateText 'codex-run'
if ($codexRun -and $codexRun -ne '-') { $unfinished += "state.md の codex-run: $codexRun" }
if ($unfinished.Count -gt 0) { $unf = (($unfinished | ForEach-Object { '- ' + $_ }) -join "`n") } else { $unf = '(なし)' }

# --- assemble -------------------------------------------------------------------
$sections = @(
    @{ N = 1; Title = 'state.md(全文)'; Body = $stateBody; Pin = $true },
    @{ N = 2; Title = '待ち'; Body = $wait; Pin = $true },
    @{ N = 3; Title = '仮説自律の否定リスト(policy.md 原文)'; Body = $neg; Pin = $true },
    @{ N = 4; Title = '制約・承認基準・終了条件(goal-frame.md 原文)'; Body = $frame; Pin = $true },
    @{ N = 5; Title = '未完了の委譲'; Body = $unf; Pin = $true },
    @{ N = 6; Title = '対象マイルストーン(goal-plan.md)'; Body = $ms; Pin = $false },
    @{ N = 7; Title = '未検証の仮定(assumptions.md)'; Body = $asm; Pin = $false },
    @{ N = 8; Title = '直近の判定'; Body = $dec; Pin = $false },
    @{ N = 9; Title = '直近 retro の「次回変えること」'; Body = $retro; Pin = $false }
)

$header = @(
    "# 再開パケット — $slug",
    '',
    "- 生成: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "- goal-dir: $GoalDir",
    "- skill-dir: $skillDir",
    "- 全文: $fullFile",
    '- このパケットは resume-packet.ps1 が state.md と正本のファイルから機械的に組んだもので、要約は含まない。再開の手順は SKILL.md の「起動時チェック」3 と「境界リセット」にある。'
) -join "`n"

function Join-Packet([hashtable]$Limits) {
    $cut = 0
    $parts = @($header)
    foreach ($s in $sections) {
        $body = [string]$s.Body
        if (-not $s.Pin -and $Limits.ContainsKey($s.N) -and $body.Length -gt $Limits[$s.N]) {
            $n = $body.Length - $Limits[$s.N]
            $body = $body.Substring(0, $Limits[$s.N]).TrimEnd() + "`n…(省略 $n 文字。全文: $fullFile)"
            $cut++
        }
        $parts += ("## $($s.N). $($s.Title)`n`n" + $body)
    }
    return @{ Text = (($parts -join "`n`n") + "`n"); Cut = $cut }
}

$full = Join-Packet @{}
Write-TextFile $fullFile $full.Text
Write-Kv 'PACKET' $fullFile
Write-Kv 'FULL_CHARS' $full.Text.Length

if ($OutFile) {
    $limits = @{}
    foreach ($k in $Caps.Keys) { $limits[$k] = $Caps[$k] }
    $packet = Join-Packet $limits
    # Still too long: shrink the cuttable sections from the back, down to MinCap each.
    foreach ($k in @(9, 8, 7, 6)) {
        if ($packet.Text.Length -le $MaxChars) { break }
        $limits[$k] = $MinCap
        $packet = Join-Packet $limits
    }
    Write-TextFile $OutFile $packet.Text
    Write-Kv 'INJECT' $OutFile
    Write-Kv 'CHARS' $packet.Text.Length
    Write-Kv 'TRUNCATED' $packet.Cut
    if ($packet.Text.Length -gt $MaxChars) {
        Write-Kv 'WARN' "packet exceeds $MaxChars chars even with every cuttable section at $MinCap; Claude Code will file it and show a 2000-char preview (state.md comes first)."
    }
}
exit 0
