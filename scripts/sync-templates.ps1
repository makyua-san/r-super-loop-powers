<#
  templates の同期・検証。
  原本: skills/r-super-loop-powers/templates
  複写先: skills-codex/r-super-loop-powers/templates
  Copy   … 原本を複写先へ上書きコピー
  Verify … 内容一致を検証し、差分があれば非ゼロ終了

  Verify の一致判定は、改行コード(CRLF/LF/CR)と先頭 BOM の差を無視した内容比較である。
  それ以外の1文字でも違えば DIFF: として検出され、非ゼロ終了する。
  .gitattributes は置かない方針。原本・複写先とも同一リポジトリ内で同一の git 設定
  (core.autocrlf 等)下にあり差は生じないはずだが、それに依存せずスクリプト側で
  改行差を吸収することで、.gitattributes によるリポジトリ全体の再正規化
  (凍結対象の Claude版 skills/ 配下を含む)を避けている。
#>
param([ValidateSet('Copy','Verify')][string]$Mode = 'Copy')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'skills\r-super-loop-powers\templates'
$dst  = Join-Path $root 'skills-codex\r-super-loop-powers\templates'

function Get-NormalizedText([string]$path) {
    $text = [System.IO.File]::ReadAllText($path)
    # 先頭のBOM(U+FEFF)を除去
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    # 改行を LF に正規化
    return $text -replace "`r`n", "`n" -replace "`r", "`n"
}

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
    $a = Get-NormalizedText (Join-Path $src $name)
    $b = Get-NormalizedText (Join-Path $dst $name)
    if ($a -ne $b) { Write-Output "DIFF: $name"; $failed = $true }
}
foreach ($name in $dstNames) {
    if ($srcNames -notcontains $name) { Write-Output "EXTRA: $name"; $failed = $true }
}

if ($failed) { Write-Output "Verify FAILED"; exit 1 }
Write-Output "Verify OK ($($srcNames.Count) templates)"
exit 0
