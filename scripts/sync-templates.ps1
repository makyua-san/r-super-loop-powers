<#
  templates の同期・検証。
  原本: skills/r-super-loop-powers/templates
  複写先: skills-codex/r-super-loop-powers/templates
  Copy   … 原本を複写先へ上書きコピー
  Verify … 内容一致を検証し、差分があれば非ゼロ終了
#>
param([ValidateSet('Copy','Verify')][string]$Mode = 'Copy')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'skills\r-super-loop-powers\templates'
$dst  = Join-Path $root 'skills-codex\r-super-loop-powers\templates'

if (-not (Test-Path $src)) { Write-Output "原本が見つかりません: $src"; exit 1 }

if ($Mode -eq 'Copy') {
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    Get-ChildItem -Path $dst -Filter *.md -File -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item -Path (Join-Path $src '*.md') -Destination $dst -Force
    $n = @(Get-ChildItem -Path $dst -Filter *.md -File).Count
    Write-Output "Copied $n templates -> $dst"
    exit 0
}

if (-not (Test-Path $dst)) { Write-Output "複写先が存在しません: $dst"; Write-Output "Verify FAILED"; exit 1 }

$srcNames = @(Get-ChildItem -Path $src -Filter *.md -File | ForEach-Object { $_.Name })
$dstNames = @(Get-ChildItem -Path $dst -Filter *.md -File | ForEach-Object { $_.Name })
$failed = $false

foreach ($name in $srcNames) {
    if ($dstNames -notcontains $name) { Write-Output "MISSING: $name"; $failed = $true; continue }
    $a = (Get-FileHash (Join-Path $src $name) -Algorithm SHA256).Hash
    $b = (Get-FileHash (Join-Path $dst $name) -Algorithm SHA256).Hash
    if ($a -ne $b) { Write-Output "DIFF: $name"; $failed = $true }
}
foreach ($name in $dstNames) {
    if ($srcNames -notcontains $name) { Write-Output "EXTRA: $name"; $failed = $true }
}

if ($failed) { Write-Output "Verify FAILED"; exit 1 }
Write-Output "Verify OK ($($srcNames.Count) templates)"
exit 0
