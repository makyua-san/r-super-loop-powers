<#
  ロール憲章の同期・検証。
  正本: skills/r-super-loop-powers/references/roles.md
  複写先: agents/builder.md の <!-- roles:begin --> 〜 <!-- roles:end --> の区間
          (中身 = 正本の「全体図 (overview)」節 + 空行 + 「実装役 (builder)」節)
  Copy   … 区間を正本から作り直す(区間の外は変えない)
  Verify … 区間が正本と一致するか検証し、違えば DIFF: を出して非ゼロ終了
  改行は LF に正規化して比較する。
#>
param(
    [ValidateSet('Copy', 'Verify')][string]$Mode = 'Copy',
    [string]$RolesFile,
    [string]$BuilderFile
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $RolesFile) { $RolesFile = Join-Path $root 'skills\r-super-loop-powers\references\roles.md' }
if (-not $BuilderFile) { $BuilderFile = Join-Path $root 'agents\builder.md' }
. (Join-Path $root 'skills\r-super-loop-powers\bin\roles-common.ps1')
$utf8 = New-Object System.Text.UTF8Encoding($false)

$charter = Get-RoleCharter -RolesFile $RolesFile -Ids @('overview', 'builder')
if (-not $charter) { Write-Output "roles sections (overview, builder) not found: $RolesFile"; Write-Output 'Verify FAILED'; exit 1 }

$text = [System.IO.File]::ReadAllText($BuilderFile, $utf8) -replace "`r`n", "`n"
$pattern = '(?s)<!-- roles:begin -->\n.*?<!-- roles:end -->'
$m = [regex]::Match($text, $pattern)
if (-not $m.Success) { Write-Output "markers not found: $BuilderFile"; Write-Output 'Verify FAILED'; exit 1 }
$region = "<!-- roles:begin -->`n" + $charter + "`n<!-- roles:end -->"

if ($Mode -eq 'Copy') {
    $new = $text.Substring(0, $m.Index) + $region + $text.Substring($m.Index + $m.Length)
    [System.IO.File]::WriteAllText($BuilderFile, $new, $utf8)
    Write-Output "Copied roles -> $BuilderFile"
    exit 0
}

if ($m.Value -ceq $region) { Write-Output 'Verify OK'; exit 0 }
Write-Output 'DIFF: agents/builder.md roles region differs from references/roles.md (run scripts/sync-roles.ps1 -Mode Copy)'
Write-Output 'Verify FAILED'
exit 1
