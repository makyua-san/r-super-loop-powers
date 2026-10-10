#Requires -Version 5.1
# Layout and wording checks for the split SKILL.md (common / workflow-a / workflow-b).
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillDir = Join-Path $root 'skills\r-super-loop-powers'
$script:failures = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}
function Get-Text([string]$Path) { if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path, $utf8) } return '' }
$skillFile = Join-Path $skillDir 'SKILL.md'
$s = Get-Text $skillFile
$a = Get-Text (Join-Path $skillDir 'references\workflow-a.md')
$b = Get-Text (Join-Path $skillDir 'references\workflow-b.md')

Check 'workflow-files-exist' ($a -ne '' -and $b -ne '') 'references/workflow-a.md / workflow-b.md missing'
Check 'skill-size' ((Get-Item -LiteralPath $skillFile).Length -le 24KB) ("SKILL.md is " + (Get-Item -LiteralPath $skillFile).Length + " bytes")
Check 'skill-points-to-workflows' ($s -match 'references/workflow-a\.md' -and $s -match 'references/workflow-b\.md') 'workflow references'
Check 'skill-common-sections' ($s -match '(?m)^## 起動時チェック' -and $s -match '(?m)^## 記録ルール' -and $s -match '(?m)^## 境界リセット' -and $s -match '(?m)^## Fableサブエージェント共通契約' -and $s -match '(?m)^## 読むものと読まないもの') 'common sections'
Check 'skill-mentions-tools' ($s -match 'loop-log\.ps1' -and $s -match 'resume-packet\.ps1' -and $s -match 'resume-pending' -and $s -match 'context-meter\.ps1' -and $s -match '再開パケット') 'tool names'
Check 'skill-recitation' ($s -match '復唱') 'recitation rule'
Check 'skill-roles-jit' ($s -match 'roles\.md' -and $s -notmatch 'policy\.md` と `references/roles\.md`\(ロール憲章\)を読む') 'roles.md must be read just in time'
Check 'skill-failures-only' ($s -match 'FAIL\\?\|ALL PASS') 'shell results: failures only'
Check 'skill-no-image-read' ($s -match 'SendUserFile') 'image rule'
# Step headings look like "**A-0 …**" or "**B-2〜B-3 …**": the number is followed by a space or 〜.
foreach ($step in @('A-0', 'A-1a', 'A-1b', 'A-5', 'A-6', 'A-7', 'A-8')) {
    Check "a-$step-in-workflow-a" ($a -match ('(?m)^\*\*' + [regex]::Escape($step) + '[ 〜]')) "$step missing in workflow-a"
    Check "a-$step-not-in-skill" ($s -notmatch ('(?m)^\*\*' + [regex]::Escape($step) + '[ 〜]')) "$step still in SKILL.md"
}
Check 'a-2-4-in-workflow-a' ($a -match '(?m)^\*\*A-2') 'A-2〜A-4 missing'
Check 'techpm-contract-in-a' ($a -match '(?m)^## 技術PM\(Codex\)共通契約' -and $s -notmatch '(?m)^## 技術PM\(Codex\)共通契約') 'techpm contract placement'
Check 'a-techpm-paths' ($a -match '40 KB' -and $a -match 'パスで渡') 'techpm prompt by path'
foreach ($step in @('B-1', 'B-2', 'B-3', 'B-4', 'B-5', 'B-6', 'B-7', 'B-8', 'B-9', 'B-10')) {
    Check "b-$step-in-workflow-b" ($b -match ('(?m)^\*\*' + [regex]::Escape($step) + '[ 〜]')) "$step missing in workflow-b"
    Check "b-$step-not-in-skill" ($s -notmatch ('(?m)^\*\*' + [regex]::Escape($step) + '[ 〜]')) "$step still in SKILL.md"
}
Check 'learning-in-b' ($b -match '(?m)^## Learning' -and $s -notmatch '(?m)^## Learning') 'Learning placement'
Check 'b2-prepare-save' ($b -match '-Prepare' -and $b -match '-SaveReport' -and $b -match '## 再委譲の差分' -and $b -match '\.prompt\.md にある') 'B-2 delegation wording'
Check 'b-grareco-low' ($b -match 'effort `low`') 'grareco effort'
Check 'b-retro-ctx' ($b -match 'CTX' -and $b -match 'RESUME') 'retro observation'
Check 'boundary-list' ($s -match '人間待ち' -and $s -match 'B-6 PASS' -and $s -match 'ACCEPT' -and $s -match 'A-8' -and $s -match '/clear') 'boundary rule'
Check 'policy-grareco-low' ((Get-Text (Join-Path $skillDir 'policy.md')) -match '`low` / read-only\(`-Role grareco`\)') 'policy.md grareco effort'
Check 'builder-read-exception' ((Get-Text (Join-Path $root 'agents\builder.md')) -match 'impl-runs/\*\.prompt\.md' -and (Get-Text (Join-Path $root 'agents\builder.md')) -match 'tech-assessment\.md') 'builder exception'
$ver = ((Get-Text (Join-Path $root '.claude-plugin\plugin.json')) | ConvertFrom-Json).version
Check 'version-0.9.0' ($ver -eq '0.9.0') "version=$ver"
& powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\sync-templates.ps1') -Mode Verify | Out-Null
Check 'templates-in-sync' ($LASTEXITCODE -eq 0) 'sync-templates Verify failed'
& powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\sync-roles.ps1') -Mode Verify | Out-Null
Check 'roles-in-sync' ($LASTEXITCODE -eq 0) 'sync-roles Verify failed'

if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
