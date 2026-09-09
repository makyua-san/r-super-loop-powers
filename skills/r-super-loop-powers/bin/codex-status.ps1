#Requires -Version 5.1
<#
  codex-status.ps1 -- decide, mechanically, what happened to a codex delegation.

  Prints "KEY: VALUE" lines ending in STATUS + NEXT. STATUS is one of:

    OK       exit 0, turn.completed seen, final message present    -> read it
    FAILED   non-zero exit, or codex reported an error event       -> do NOT proceed
    TIMEOUT  killed at the timeout, or no exit before -WaitMinutes -> do NOT proceed
    SUSPECT  exit 0 but no turn.completed or no final message      -> do NOT proceed
    BLOCKED  the run finished but the report says it was blocked    -> do NOT proceed
    INCOMPLETE  finished, but criteria unmet / nothing verified     -> do NOT proceed
    CONTRACT_VIOLATION  the report admits it committed              -> inspect git first
    RUNNING  still working, events still arriving                  -> poll again
    STALLED  alive but silent for -StallMinutes                    -> decide: wait or abort
    LOST     process gone without writing an exit file             -> re-run, nothing was recorded

  Exit code: 0 for OK, 1 for every other status. "The process disappeared" is never
  by itself treated as success -- that conflation is what silently swallowed failed
  and half-finished delegations.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RunDir,
    [Parameter(Mandatory = $true)][string]$Label,
    [int]$WaitMinutes = 0,
    [int]$StallMinutes = 10,
    [int]$Tail = 10,
    [switch]$Abort
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'codex-common.ps1')

if (-not (Test-Path -LiteralPath $RunDir)) { throw "RunDir does not exist: $RunDir" }
$RunDir = (Resolve-Path -LiteralPath $RunDir).Path

$exitFile = Join-Path $RunDir "$Label.exit"
$doneFile = Join-Path $RunDir "$Label.done.json"
$metaFile = Join-Path $RunDir "$Label.meta.json"
$outFile = Join-Path $RunDir "$Label.out.jsonl"
$errFile = Join-Path $RunDir "$Label.err.txt"
$lastFile = Join-Path $RunDir "$Label.last.txt"
$pidFile = Join-Path $RunDir "$Label.pid"
$childPidFile = Join-Path $RunDir "$Label.child.pid"

if (-not (Test-Path -LiteralPath $metaFile)) {
    throw "no run named '$Label' in $RunDir (missing $Label.meta.json). Check the label."
}
$meta = Read-TextFile $metaFile | ConvertFrom-Json

function Get-PidFrom([string]$Path) {
    $value = 0
    if (Test-Path -LiteralPath $Path) { [void][int]::TryParse((Read-TextFile $Path).Trim(), [ref]$value) }
    return $value
}
$workerPid = Get-PidFrom $pidFile
$childPid = Get-PidFrom $childPidFile

# --- abort --------------------------------------------------------------------
if ($Abort) {
    Stop-ProcessTree $childPid
    Stop-ProcessTree $workerPid
    if (-not (Test-Path -LiteralPath $exitFile)) {
        $aborted = [ordered]@{ label = $Label; exitCode = 130; timedOut = $false; note = 'aborted by orchestrator'; endedAt = (Get-Date).ToString('s') }
        Write-TextFile $doneFile ($aborted | ConvertTo-Json -Depth 4)
        Write-ExitFile $exitFile '130'
    }
    Write-Kv 'STATUS' 'FAILED'
    Write-Kv 'REASON' 'aborted by orchestrator'
    Write-Kv 'NEXT' 'Record the abort in call-log.md, then re-run with a narrower scope or a lower effort.'
    exit 1
}

# --- optional bounded wait ----------------------------------------------------
# Capped at 9 minutes so one call still fits inside a 10-minute tool timeout.
if ($WaitMinutes -gt 0) {
    if ($WaitMinutes -gt 9) { $WaitMinutes = 9 }
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $exitFile)) {
        Start-Sleep -Seconds 5
    }
}

# --- parse the event stream ---------------------------------------------------
$events = 0
$turnCompleted = 0
$turnFailed = 0
$errorCount = 0
$commandCount = 0
$reasoningCount = 0
$agentMessages = 0
$tokens = 0
$threadId = ''
# Item-level "error" entries are often warnings (e.g. unknown model metadata) that
# precede the real failure, so keep the fatal signal separate and prefer it.
$fatalError = ''
$softError = ''
$recent = New-Object System.Collections.ArrayList
$boundaryHits = New-Object System.Collections.ArrayList

# Paths the execution contract puts off limits. Codex wandering into them is the
# classic wasted run: it reads orchestrator files instead of the repository.
$boundaryPattern = '(\.claude[\\/])|(\.codex[\\/])|(\.agents[\\/])|(SKILL\.md)|([\\/]skills[\\/])'

if (Test-Path -LiteralPath $outFile) {
    $reader = New-Object System.IO.StreamReader($outFile, [System.Text.Encoding]::UTF8)
    try {
        while (($line = $reader.ReadLine()) -ne $null) {
            if (-not $line.Trim()) { continue }
            $ev = $null
            try { $ev = $line | ConvertFrom-Json } catch { continue }
            $events++
            switch ($ev.type) {
                'thread.started' { if ($ev.thread_id) { $threadId = [string]$ev.thread_id } }
                'turn.completed' {
                    $turnCompleted++
                    if ($ev.usage) {
                        $inTok = 0; $outTok = 0
                        if ($ev.usage.input_tokens) { $inTok = [int]$ev.usage.input_tokens }
                        if ($ev.usage.output_tokens) { $outTok = [int]$ev.usage.output_tokens }
                        $tokens += $inTok + $outTok
                    }
                }
                'turn.failed' {
                    $turnFailed++
                    if (-not $fatalError -and $ev.error) { $fatalError = [string]$ev.error.message }
                }
                'error' {
                    $errorCount++
                    if (-not $fatalError) { $fatalError = [string]$ev.message }
                }
                'item.completed' {
                    if (-not $ev.item) { continue }
                    switch ($ev.item.type) {
                        'command_execution' {
                            $commandCount++
                            $cmd = [string]$ev.item.command
                            if ($cmd) {
                                [void]$recent.Add('ran: ' + ($cmd -replace '\s+', ' '))
                                if ($cmd -match $boundaryPattern) { [void]$boundaryHits.Add(($cmd -replace '\s+', ' ')) }
                            }
                        }
                        'reasoning' {
                            $reasoningCount++
                            $t = [string]$ev.item.text
                            if ($t) { [void]$recent.Add('thinking: ' + ($t -replace '\s+', ' ')) }
                        }
                        'agent_message' { $agentMessages++ }
                        'error' {
                            $errorCount++
                            if (-not $softError) { $softError = [string]$ev.item.message }
                        }
                    }
                }
            }
        }
    } finally { $reader.Dispose() }
}

$firstError = $fatalError
if (-not $firstError) { $firstError = $softError }

$errText = Read-TextFile $errFile
$errTail = ($errText -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | '
$authSmell = ($errText -match '(?i)\b(unauthorized|not authenticated|please run codex login|401)\b')

# On Windows this one is nasty: codex starts, cannot build its sandbox, and every
# shell command it tries is rejected -- so it "finishes" having done nothing.
$sandboxSmell = ($errText -match '(?i)windows sandbox|writable root capability SIDs|CreateProcessWithLogonW')

$finalMessage = Read-TextFile $lastFile
$finalBytes = [System.Text.Encoding]::UTF8.GetByteCount($finalMessage)

# --- liveness -----------------------------------------------------------------
$now = Get-Date
$startedAt = $now
if ($meta.startedAt) { $startedAt = [datetime]::Parse($meta.startedAt) }
$elapsedSec = [int]($now - $startedAt).TotalSeconds

$lastEventAgeSec = -1
if (Test-Path -LiteralPath $outFile) {
    $lastEventAgeSec = [int]($now - (Get-Item -LiteralPath $outFile).LastWriteTime).TotalSeconds
}

$exitCode = $null
$timedOut = $false
$doneNote = ''
if (Test-Path -LiteralPath $exitFile) {
    $raw = (Read-TextFile $exitFile).Trim()
    $parsed = 0
    if ([int]::TryParse($raw, [ref]$parsed)) { $exitCode = $parsed } else { $exitCode = 250 }
    if (Test-Path -LiteralPath $doneFile) {
        try {
            $done = Read-TextFile $doneFile | ConvertFrom-Json
            if ($done.timedOut) { $timedOut = [bool]$done.timedOut }
            if ($done.note) { $doneNote = [string]$done.note }
        } catch { }
    }
}

# --- verdict ------------------------------------------------------------------
$status = ''
$reason = ''
$next = ''

if ($null -ne $exitCode) {
    if ($timedOut -or $exitCode -eq 124) {
        $status = 'TIMEOUT'
        $reason = "codex was killed at the timeout ($($meta.timeoutMinutes) min). $doneNote"
        $next = 'Split the delegation into smaller scopes, or lower the effort, then re-run. Files it already wrote are on disk -- check git status before re-running.'
    } elseif ($exitCode -ne 0) {
        $status = 'FAILED'
        $reason = "codex exited $exitCode. " + $(if ($firstError) { $firstError } else { $errTail })
        $next = 'Do NOT treat this milestone as implemented. Fix the cause and re-run; if it is auth or model availability, report it to the human and stop.'
    } elseif ($turnFailed -gt 0) {
        $status = 'FAILED'
        $reason = "codex reported turn.failed. $firstError"
        $next = 'Do NOT treat this milestone as implemented. Re-run after addressing the reported error.'
    } elseif ($turnCompleted -lt 1) {
        $status = 'SUSPECT'
        $reason = 'exit 0 but no turn.completed event -- the stream ended mid-turn.'
        $next = 'Treat as a failed run. Re-run the delegation.'
    } elseif ($finalBytes -eq 0) {
        $status = 'SUSPECT'
        $reason = 'the run completed but wrote no final message, so there is no self-verification report to accept.'
        $next = 'Treat as a failed run. Re-run, and keep contract item 5 (final message is the only output) in the prompt.'
    } else {
        $status = 'OK'
        $reason = "exit 0, turn.completed x$turnCompleted, final message $finalBytes bytes"
        $next = "Read the report: $lastFile"
    }
} else {
    $alive = (Test-PidAlive $workerPid) -or (Test-PidAlive $childPid)
    if (-not $alive) {
        $status = 'LOST'
        $reason = 'the process is gone but never wrote an exit file -- it was killed from outside (session teardown, reboot, or an external kill).'
        $next = 'Nothing was recorded as finished. Check git status for partial work, then re-run.'
    } elseif ($lastEventAgeSec -ge ($StallMinutes * 60)) {
        $status = 'STALLED'
        $reason = "alive, but no new event for $lastEventAgeSec s (threshold $($StallMinutes * 60) s)."
        $next = "Wait one more poll, then abort if still silent: codex-status.ps1 -RunDir '$RunDir' -Label '$Label' -Abort"
    } else {
        $status = 'RUNNING'
        $reason = "$events events, last one $lastEventAgeSec s ago"
        $next = "Poll again: codex-status.ps1 -RunDir '$RunDir' -Label '$Label' -WaitMinutes 9"
    }
}

# --- report -------------------------------------------------------------------
Write-Kv 'LABEL' $Label
Write-Kv 'RUN_DIR' $RunDir
Write-Kv 'MODEL' $meta.model
Write-Kv 'EFFORT' $meta.effort
Write-Kv 'ELAPSED_SEC' $elapsedSec
Write-Kv 'LAST_EVENT_AGE_SEC' $lastEventAgeSec
if ($null -ne $exitCode) { Write-Kv 'EXIT_CODE' $exitCode } else { Write-Kv 'EXIT_CODE' '(not written yet)' }
Write-Kv 'EVENTS' ("total=$events turn.completed=$turnCompleted turn.failed=$turnFailed errors=$errorCount commands=$commandCount reasoning=$reasoningCount agent_messages=$agentMessages")
Write-Kv 'TOKENS' $tokens
if ($threadId) { Write-Kv 'THREAD_ID' $threadId }
Write-Kv 'FINAL_MESSAGE_FILE' $lastFile
Write-Kv 'FINAL_MESSAGE_BYTES' $finalBytes
if ($meta.outputSchema -and $finalBytes -gt 0) {
    $report = $null
    try { $report = $finalMessage | ConvertFrom-Json } catch { $report = $null }
    Write-Kv 'FINAL_MESSAGE_JSON' $(if ($report) { 'VALID' } else { 'INVALID' })
    if (-not $report -and $status -eq 'OK') {
        $status = 'SUSPECT'
        $reason = 'the run completed but the final message is not valid JSON despite --output-schema.'
        $next = 'Re-run without -OutputSchema and require the report as a fenced JSON block in the prompt instead.'
    }

    # A finished process is not a finished milestone. When the report is an
    # impl-report, read what it actually says -- a run that stopped blocked, or
    # met none of its criteria, must not read as green just because it exited 0.
    if ($report -and $status -eq 'OK' -and ($report.PSObject.Properties.Name -contains 'blocked')) {
        $changed = @()
        if ($report.changed_files) { $changed = @($report.changed_files) }
        $failedChecks = @()
        if ($report.verification) { $failedChecks = @($report.verification | Where-Object { $_.outcome -eq 'FAIL' }) }
        $ranChecks = @()
        if ($report.verification) { $ranChecks = @($report.verification | Where-Object { $_.outcome -ne 'SKIPPED' }) }
        $unmet = @()
        if ($report.acceptance_criteria) { $unmet = @($report.acceptance_criteria | Where-Object { $_.status -ne 'MET' }) }

        Write-Kv 'REPORT' ("blocked=$($report.blocked) committed=$($report.committed) changed_files=$($changed.Count) verifications_run=$($ranChecks.Count) verifications_failed=$($failedChecks.Count) criteria_unmet=$($unmet.Count)")
        foreach ($u in ($unmet | Select-Object -First 5)) { Write-Kv 'CRITERION_UNMET' ("[$($u.status)] $($u.criterion)") }
        if ($report.new_assumptions) {
            foreach ($a in @($report.new_assumptions)) { Write-Kv 'NEW_ASSUMPTION' $a }
        }
        if ($report.unresolved) {
            foreach ($u in @($report.unresolved)) { Write-Kv 'UNRESOLVED' $u }
        }

        if ($report.committed -eq $true) {
            $status = 'CONTRACT_VIOLATION'
            $reason = 'codex reports that it committed. The execution contract forbids commits -- the orchestrator owns the history.'
            $next = 'Inspect git log / git status before anything else, undo the commit if it is not wanted, then decide whether to keep the work.'
        } elseif ($report.blocked -eq $true) {
            $status = 'BLOCKED'
            $reason = "codex stopped without finishing: $($report.blocked_reason)"
            $next = 'Do NOT advance the milestone. Resolve the blocker (or escalate per policy.md B-4) and re-run.'
        } elseif ($unmet.Count -gt 0 -or $failedChecks.Count -gt 0) {
            $status = 'INCOMPLETE'
            $reason = "$($unmet.Count) acceptance criteria unmet, $($failedChecks.Count) verification(s) failed."
            $next = 'Re-run with the specific gaps quoted back to codex. Do NOT write submission.md from this run.'
        } elseif ($changed.Count -eq 0) {
            $status = 'INCOMPLETE'
            $reason = 'the report claims success but lists no changed files.'
            $next = 'Check git status yourself. If nothing changed, re-run with a concrete file list in the prompt.'
        } elseif ($ranChecks.Count -eq 0) {
            $status = 'INCOMPLETE'
            $reason = 'no verification was actually run, so there is no evidence to submit (PL-004).'
            $next = 'Re-run and require at least one executed verification command tied to the acceptance criteria.'
        }
    }
}
if ($firstError) { Write-Kv 'ERROR' $firstError }
if ($errTail) { Write-Kv 'STDERR_TAIL' $errTail }
if ($authSmell) { Write-Kv 'WARN' 'stderr looks like an auth failure. Run: codex login' }
if ($sandboxSmell) { Write-Kv 'WARN' 'codex could not build its Windows sandbox, so its shell commands were rejected. This is usually double-sandboxing (an outer sandbox around codex). Re-run the delegation from an unsandboxed shell.' }
if ($boundaryHits.Count -gt 0) {
    Write-Kv 'WARN' ("codex touched $($boundaryHits.Count) off-limits path(s) -- it may have read orchestrator files instead of the repo. Consider re-running with a tighter scope.")
    foreach ($h in ($boundaryHits | Select-Object -First 3)) { Write-Kv 'BOUNDARY_HIT' $h.Substring(0, [Math]::Min(160, $h.Length)) }
}
foreach ($r in ($recent | Select-Object -Last $Tail)) {
    Write-Kv 'RECENT' $r.Substring(0, [Math]::Min(200, $r.Length))
}

Write-Kv 'STATUS' $status
Write-Kv 'REASON' $reason
Write-Kv 'NEXT' $next

if ($status -eq 'OK') { exit 0 }
exit 1
