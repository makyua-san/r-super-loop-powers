#Requires -Version 5.1
<#
  human-message-check.ps1 -- Stop hook for r-super-loop-powers.

  While a goal loop is active in the session's cwd (docs/r-super-loop-powers/*/state.md
  with a phase other than done), the reply the human reads must be Japanese and easy
  to act on. A failing reply is sent back once with {"decision":"block"} so the
  orchestrator rewrites it; stop_hook_active=true means that rewrite already happened.

  Checks, cheapest first:
    1. Japanese ratio J / (J + W): J = kana/kanji characters, W = English words, after
       code, URLs and paths are removed. English counts per word so a Japanese sentence
       full of tool names does not fail.
    2. A small model (claude -p --model haiku) judges clarity with hooks/judge-prompt.md.

  Fail-open: any failure of the judge or of this script lets the reply through and is
  written to <goal-dir>/hook-log.md. A broken checker must never trap the session.

  Env:
    RSLP_HOOK_CHILD=1  set on the judge's own claude session so this hook skips there
    RSLP_JUDGE_CMD     test seam: .exe/.cmd that reads the judge prompt on stdin
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hook-common.ps1')

$JaRatioMin = 0.6
$MinUnits = 20
$JudgeTimeoutSec = 60
$JudgeModel = 'haiku'

function Get-ProseText([string]$Text) {
    # Fenced blocks (``` or ~~~), including one left open at the end of the reply.
    $t = [regex]::Replace($Text, '(?s)```.*?```', ' ')
    $t = [regex]::Replace($t, '(?s)~~~.*?~~~', ' ')
    $t = [regex]::Replace($t, '(?s)(```|~~~).*$', ' ')
    $t = [regex]::Replace($t, '`[^`\r\n]*`', ' ')
    $t = [regex]::Replace($t, 'https?://\S+', ' ')
    $t = [regex]::Replace($t, '(?i)\b[a-z]:\\\S*', ' ')
    $t = [regex]::Replace($t, '[A-Za-z0-9_.~-]*(?:[/\\][A-Za-z0-9_.-]+)+', ' ')
    return $t
}

function Get-JaStats([string]$Prose) {
    $j = [regex]::Matches($Prose, '[\p{IsHiragana}\p{IsKatakana}\p{IsCJKUnifiedIdeographs}]').Count
    $w = [regex]::Matches($Prose, '[A-Za-z]+').Count
    $ratio = 1.0
    if (($j + $w) -gt 0) { $ratio = $j / ($j + $w) }
    return [pscustomobject]@{ J = $j; W = $w; Units = $j + $w; Ratio = $ratio }
}

function Invoke-Judge([string]$Prompt) {
    $exe = $env:RSLP_JUDGE_CMD
    if (-not $exe) {
        $cmd = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { throw 'claude CLI not found on PATH' }
        $exe = $cmd.Source
    }
    $settings = Join-Path ([System.IO.Path]::GetTempPath()) 'rslp-judge-settings.json'
    if (-not (Test-Path -LiteralPath $settings)) {
        [System.IO.File]::WriteAllText($settings, '{"disableAllHooks":true}', $Utf8)
    }
    # The reply under judgement is untrusted text: the judge gets no tools and no
    # MCP servers (which also makes it start faster).
    $argList = @('-p', '--model', $JudgeModel, '--output-format', 'text', '--settings', $settings,
        '--tools', '', '--strict-mcp-config')
    $quoted = ($argList | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($exe -match '\.(cmd|bat)$') {
        $psi.FileName = $env:ComSpec
        $psi.Arguments = '/d /s /c ""' + $exe + '" ' + $quoted + '"'
    } else {
        $psi.FileName = $exe
        $psi.Arguments = $quoted
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Utf8
    $psi.StandardErrorEncoding = $Utf8
    # Outside the project so the judge does not load its CLAUDE.md.
    $psi.WorkingDirectory = [System.IO.Path]::GetTempPath()
    $psi.EnvironmentVariables['RSLP_HOOK_CHILD'] = '1'

    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEndAsync()
    $stderr = $p.StandardError.ReadToEndAsync()
    try {
        $bytes = $Utf8.GetBytes($Prompt)
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $p.StandardInput.Close()
    } catch { }   # the judge may exit without reading stdin; its output still decides
    if (-not $p.WaitForExit($JudgeTimeoutSec * 1000)) {
        & taskkill /T /F /PID $p.Id 2>$null | Out-Null
        throw "judge timed out after $JudgeTimeoutSec s"
    }
    $p.WaitForExit()
    $text = $stdout.Result
    if ($p.ExitCode -ne 0) { throw "judge exited $($p.ExitCode): $($stderr.Result.Trim())" }
    $m = [regex]::Match($text, '\{[^{}]*"ok"\s*:\s*(true|false)[^{}]*\}')
    if (-not $m.Success) { throw "judge output has no verdict: $($text.Trim())" }
    return ($m.Value | ConvertFrom-Json)
}

function Send-Block([string]$Why) {
    # The template adds its own full stop after the reason.
    $Why = $Why.Trim().TrimEnd([char[]]@([char]0x3002, '.'))
    $reason = "[r-super-loop-powers] 人間向けの応答を書き直してください: $Why。内容は変えず、日本語で、結論・お願いしたいことを冒頭に、内部用語は言い換えて端的に。"
    Write-StdoutUtf8 (@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress)
}

# ---- main ----
if ($env:RSLP_HOOK_CHILD -eq '1') { exit 0 }
try { $hookInput = Read-StdinUtf8 | ConvertFrom-Json } catch { exit 0 }
if (-not $hookInput) { exit 0 }
if ($hookInput.stop_hook_active -eq $true) { exit 0 }
$message = [string]$hookInput.last_assistant_message
if (-not $message.Trim()) { exit 0 }
$cwd = [string]$hookInput.cwd
if (-not $cwd) { $cwd = (Get-Location).Path }
$goalDir = $null
try { $goalDir = Find-GoalDir $cwd } catch { exit 0 }
if (-not $goalDir) { exit 0 }

$ratioText = '-'
try {
    $stats = Get-JaStats (Get-ProseText $message)
    $ratioText = '{0:0.00}' -f $stats.Ratio
    if ($stats.Units -ge $MinUnits -and $stats.Ratio -lt $JaRatioMin) {
        Send-Block "日本語で書かれていません(日本語の比率 $ratioText、基準 $JaRatioMin)。ユーザーが英語の文面そのものを求めた場合は、その文面はコードブロックに入れ、説明は日本語で書いてください"
        Write-HookLogLine $goalDir 'BLOCK' "ja-ratio=$ratioText" 'not japanese'
        exit 0
    }
    $template = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'judge-prompt.md'), $Utf8)
    $verdict = Invoke-Judge ($template.Replace('{{MESSAGE}}', $message))
    if ($verdict.ok -eq $false) {
        $why = [string]$verdict.reason
        if (-not $why.Trim()) { $why = '分かりにくい箇所があります' }
        Send-Block $why
        Write-HookLogLine $goalDir 'BLOCK' "ja-ratio=$ratioText" $why
    } else {
        Write-HookLogLine $goalDir 'PASS' "ja-ratio=$ratioText" ''
    }
} catch {
    Write-HookLogLine $goalDir 'ERROR' "ja-ratio=$ratioText" $_.Exception.Message
}
exit 0
