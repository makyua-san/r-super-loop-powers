#Requires -Version 5.1
<#
  codex-run.ps1 -- launch one codex delegation and return immediately.

  The launcher validates everything it can before spending a token, then starts a
  detached worker. The worker runs codex, waits with a hard timeout, and ALWAYS
  writes <Label>.exit last. The existence of that file is the only completion
  signal anyone needs; its contents say whether it worked.

  Poll with codex-status.ps1 -RunDir <dir> -Label <label>.

  Artifacts under -RunDir:
    <Label>.prompt.txt   normalized prompt actually sent (contract + your text)
    <Label>.out.jsonl    codex --json event stream (progress AND completion)
    <Label>.err.txt      codex stderr
    <Label>.last.txt     codex final message (-o)
    <Label>.exit         exit code, written last, never partially
    <Label>.done.json    exit code, timedOut flag, timings
    <Label>.meta.json    how it was launched
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EnvFile,
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string]$PromptFile,
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [string]$RunDir,
    # Who codex is in this delegation. Every role is read-only: implementation is
    # done by the Claude-side builder agent, so codex never needs to write.
    [Parameter(Mandatory = $true)][ValidateSet('techpm', 'reviewer', 'grareco')][string]$Role,
    [string]$Model,
    # Empty = role default (techpm / reviewer: max, grareco: low).
    [ValidateSet('', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra')][string]$Effort = '',
    [string[]]$AddDir = @(),
    [int]$TimeoutMinutes = 60,
    [switch]$NoPreamble,
    # Plugins stay off by default: the user-level superpowers plugin makes codex
    # open brainstorming/writing-plans instead of answering (seen in 36 of 37 runs).
    # Built-in system skills (imagegen etc.) remain.
    [switch]$KeepPlugins,
    # Source of the role charter (process map + this role's section). Empty = the
    # skill's references/roles.md. Tests point it elsewhere.
    [string]$RolesFile,
    # internal
    [switch]$Worker,
    [string]$JobFile
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'codex-common.ps1')
. (Join-Path $PSScriptRoot 'roles-common.ps1')

# The orchestrator's non-negotiables, prepended to every prompt so they cannot be
# forgotten by whoever writes the task text. Item 5 matters most: the final
# message is the only thing that is read back.
$ExecutionContract = @'
== EXECUTION CONTRACT (from the orchestrator -- read before anything else) ==
1. SCOPE. Work only inside your working directory. Do NOT read, execute, or modify
   anything under ~/.claude/, .claude/, ~/.codex/, .codex/, ~/.agents/, or any
   skills/ or SKILL.md path. Those belong to a different agent system; opening them
   burns the run and counts as a failed delegation.
2. NO COMMITS. Never run git commit, git push, git reset --hard, git rebase, or any
   history-rewriting command. The orchestrator owns the history.
3. NO REDEFINING THE GOAL. Do not restate, narrow, or replace the requirements and
   acceptance criteria you were given. If they conflict or you cannot proceed, say
   exactly that in your final message and stop.
4. STOP INSTEAD OF DECIDING ALONE on: irreversible operations (deleting or
   overwriting data), anything that publishes or transmits outside this machine,
   money or contracts, auth / security / personal-data handling, and destructive
   changes to an approved design. Report and stop.
5. YOUR FINAL MESSAGE IS THE ONLY OUTPUT THAT IS READ. Streamed progress is not
   read back. Put your complete answer in the final message.
6. If you finish early because you are blocked, say so explicitly in the final
   message. Silence is read as a failed run, not as success.
7. READ-ONLY. Your sandbox is read-only. Do not create, modify, or delete any file.
   Everything you produce goes in your final message (the built-in image_gen tool
   is the only exception; it stores its image outside the working directory).
== END EXECUTION CONTRACT ==

'@

# Role briefs, prepended after the contract. They exist because the model's default
# on a feature-sized task is to design and plan first; here that work is already
# done and approved upstream, so re-doing it costs time and risks drifting from it.
$RoleBriefs = @{
    techpm = @'
== ROLE: TECH PM (advisor, read-only) ==
You are the technical lead who will be accountable for implementing this goal.
Answer the numbered HOW questions from the implementer's point of view, grounded
in the actual code (read it). You do not write or change code, and you do not
approve the design. Do not invoke process skills (brainstorming, writing-plans or
similar) -- the orchestrator runs that process; your job is only the answers it
asked for. Decisions about user value, preferences, or priorities are not yours:
return them as "NEEDS_USER_VIEW: <question>".
Be concrete enough that a builder can execute your answer without re-deciding it:
name files, functions, the approach, the order of work, the known risks with how
to avoid them, and the command that proves it works.
== END ROLE ==

'@
    reviewer = @'
== ROLE: TECH REVIEWER (read-only) ==
You review ONE milestone that a separate builder has just implemented. You are not
the builder and you fix nothing.
- Review TECHNICAL quality only: correctness, consistency with the TECHNICAL
  ASSESSMENT / approved plan, risks (security, data loss, compatibility,
  concurrency), and whether the verification really proves the acceptance
  criteria. Inspect the real change yourself: run git diff <base> against the
  base ref given in the task AND git status --porcelain --untracked-files=all,
  then read untracked files directly (git diff does not show new files).
- Do NOT judge whether the milestone meets the user's requirements or goal; a
  different reviewer owns that. Do not invoke process skills.
- For each finding give: severity (HIGH / MEDIUM / LOW), evidence (file:line or
  command output), recommended fix. No findings is a valid answer.
- End with exactly one line: "TECH_REVIEW: OK" (no HIGH finding) or
  "TECH_REVIEW: CONCERNS" (at least one HIGH finding).
== END ROLE ==

'@
    # image_gen is a built-in tool. Its system skill (~/.codex/skills/.system/imagegen/
    # SKILL.md) costs ~15 round trips per run when read first (survey 2026-10-10), so the
    # brief says to call the tool directly; reading that one SKILL.md stays allowed only
    # if the tool refuses to run without it (v0.8.1 lesson: two runs ended with no image).
    grareco = @'
== ROLE: GRAPHIC RECORDER ==
Read only the input file named in the task. Generate the image with your built-in
image_gen tool and do not try to save or copy it anywhere -- the orchestrator
collects it.
Do not read the imagegen system skill (SKILL.md under ~/.codex/skills/.system/imagegen/)
first: call image_gen directly. EXCEPTION to contract item 1, only if the tool refuses
to run without it: you MAY read that one SKILL.md. Nothing else under skills/,
SKILL.md, ~/.codex/ or ~/.claude/.
If you did not actually call image_gen (or it failed), your final message MUST
start with "NO_IMAGE_GENERATED:" and the reason. Never say an image was made
unless image_gen returned one; the orchestrator checks for the file.
== END ROLE ==

'@
}

# Documented effort ladders: Sol and Luna stop at max (no "ultra"). Sending ultra
# to them fails the run, so clamp here instead of burning a delegation.
$NoUltraModels = @('gpt-6-sol', 'gpt-6.1-sol', 'gpt-6-luna', 'gpt-5.6-luna')

# ============================================================================
# Worker
# ============================================================================
if ($Worker) {
    $job = Read-TextFile $JobFile | ConvertFrom-Json
    $runDir = $job.runDir
    $label = $job.label
    $exitFile = Join-Path $runDir "$label.exit"
    $doneFile = Join-Path $runDir "$label.done.json"
    $logFile = Join-Path $runDir "$label.worker.log"
    $startedAt = Get-Date

    function Write-WorkerLog([string]$Text) {
        $line = "{0}  {1}`r`n" -f (Get-Date).ToString('s'), $Text
        try { [System.IO.File]::AppendAllText($logFile, $line) } catch { }
    }

    $exitCode = 250
    $timedOut = $false
    $note = ''
    try {
        Write-WorkerLog "worker start: $($job.file) $($job.argLine)"
        # Win32_Process.Create does not pass the launcher's environment on, so
        # without this codex falls back to ~/.codex: a different auth and config
        # than the preflight checked, and images land where nobody looks (issue #4).
        if ($job.codexHome) { $env:CODEX_HOME = $job.codexHome }
        $p = Register-ProcessHandle (Start-Process -FilePath $job.file -ArgumentList $job.argLine `
                -RedirectStandardInput $job.promptFile `
                -RedirectStandardOutput $job.outFile `
                -RedirectStandardError $job.errFile `
                -NoNewWindow -PassThru)
        Write-TextFile (Join-Path $runDir "$label.child.pid") ([string]$p.Id)
        Write-WorkerLog "codex pid: $($p.Id)"

        if ($p.WaitForExit($job.timeoutMinutes * 60 * 1000)) {
            $exitCode = Get-ProcessExitCode $p
            if ($null -eq $exitCode) {
                $exitCode = 251
                $note = 'codex exited but its exit code could not be read'
            }
            Write-WorkerLog "codex exited: $exitCode"
        } else {
            $timedOut = $true
            $note = "killed after $($job.timeoutMinutes) minutes"
            Write-WorkerLog "TIMEOUT -- $note"
            Stop-ProcessTree $p.Id
            $exitCode = 124
        }
    } catch {
        $note = "worker error: $($_.Exception.Message)"
        $exitCode = 250
        Write-WorkerLog $note
    } finally {
        $endedAt = Get-Date
        $done = [ordered]@{
            label       = $label
            exitCode    = $exitCode
            timedOut    = $timedOut
            note        = $note
            startedAt   = $startedAt.ToString('s')
            endedAt     = $endedAt.ToString('s')
            durationSec = [int]($endedAt - $startedAt).TotalSeconds
        }
        try { Write-TextFile $doneFile ($done | ConvertTo-Json -Depth 4) } catch { }
        # Written last, via rename: a reader never sees a half-written exit file.
        Write-ExitFile $exitFile ([string]$exitCode)
    }
    exit 0
}

# ============================================================================
# Launcher
# ============================================================================
$codexEnv = Import-CodexEnv $EnvFile
$inv = Get-CodexInvocation $codexEnv

if (-not (Test-Path -LiteralPath $WorkDir)) { throw "WorkDir does not exist: $WorkDir" }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
if (-not (Test-Path -LiteralPath $PromptFile)) { throw "PromptFile does not exist: $PromptFile" }
$PromptFile = (Resolve-Path -LiteralPath $PromptFile).Path

if ($Label -notmatch '^[A-Za-z0-9._-]+$') { throw "Label must be [A-Za-z0-9._-]+ (got: $Label)" }


# Every codex role is advisory (SKILL.md gate rule 10). Implementation happens in
# the Claude-side builder agent, so there is no write path here at all.
$Sandbox = 'read-only'
if (-not $Effort) {
    if ($Role -eq 'grareco') { $Effort = 'low' } else { $Effort = 'max' }
}

if (-not $RunDir) { $RunDir = Join-Path $WorkDir '.codex-runs' }
if (-not (Test-Path -LiteralPath $RunDir)) { New-Item -ItemType Directory -Path $RunDir -Force | Out-Null }
$RunDir = (Resolve-Path -LiteralPath $RunDir).Path

# Refuse to silently overwrite a run that is still going.
$exitFile = Join-Path $RunDir "$Label.exit"
$pidFile = Join-Path $RunDir "$Label.pid"
if ((Test-Path -LiteralPath $pidFile) -and -not (Test-Path -LiteralPath $exitFile)) {
    $oldPid = 0
    [void][int]::TryParse((Read-TextFile $pidFile).Trim(), [ref]$oldPid)
    if (Test-PidAlive $oldPid) {
        throw "label '$Label' is already running (pid $oldPid). Use a new label, or abort it: codex-status.ps1 -RunDir '$RunDir' -Label '$Label' -Abort"
    }
}

$rawPrompt = Read-TextFile $PromptFile
if (-not $rawPrompt.Trim()) { throw "PromptFile is empty: $PromptFile" }

# Normalize to UTF-8 without BOM and prepend the contract. A BOM on stdin shows up
# as a stray character in the first instruction.
$warnings = @()
# A 300 KB prompt was measured once (hearing-log + spec + plan pasted whole). codex is
# read-only but can READ: pass documents by path instead of pasting them.
$promptBytes = [System.Text.Encoding]::UTF8.GetByteCount($rawPrompt)
if ($promptBytes -gt 40960) {
    $warnings += ("prompt is {0} KB (> 40 KB); pass long documents by path and let codex read them." -f [int][Math]::Ceiling($promptBytes / 1024.0))
}
$normalizedPrompt = Join-Path $RunDir "$Label.prompt.txt"
if ($NoPreamble) {
    Write-TextFile $normalizedPrompt $rawPrompt
} else {
    # The charter tells codex where it sits in the whole loop and who decides what
    # it must not (references/roles.md). A missing charter degrades the prompt but
    # must not stop a delegation.
    if (-not $RolesFile) { $RolesFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'references\roles.md' }
    $charter = Get-RoleCharter -RolesFile $RolesFile -Ids @('overview', $Role)
    $charterBlock = ''
    if ($charter) {
        $charterBlock = "== ROLE CHARTER (your place in the whole process; from references/roles.md) ==`n" + $charter + "`n== END ROLE CHARTER ==`n`n"
    } else {
        $warnings += "roles section not found in $RolesFile; the prompt goes out without the role charter."
    }
    Write-TextFile $normalizedPrompt ($ExecutionContract + $charterBlock + $RoleBriefs[$Role] + $rawPrompt)
}

$outFile = Join-Path $RunDir "$Label.out.jsonl"
$errFile = Join-Path $RunDir "$Label.err.txt"
$lastFile = Join-Path $RunDir "$Label.last.txt"
foreach ($stale in @($outFile, $errFile, $lastFile, $exitFile, (Join-Path $RunDir "$Label.done.json"))) {
    Remove-Item -LiteralPath $stale -Force -ErrorAction SilentlyContinue
}


if (-not $Model) { $Model = [string]$codexEnv.model }
$legacyKeys = @('techpmModel', 'sandbox', 'sandboxWriteOk', 'writableRoots', 'builderFallbackFrom') |
    Where-Object { $codexEnv.PSObject.Properties.Name -contains $_ }
# envSchema 2 = written by the v0.7 preflight. The model name is NOT a criterion:
# a model the user named with -Model is legitimate and must not warn forever.
$envSchema = 0
if ($codexEnv.PSObject.Properties.Name -contains 'envSchema') { [void][int]::TryParse([string]$codexEnv.envSchema, [ref]$envSchema) }
if ($legacyKeys -or $envSchema -lt 2) {
    $warnings += "codex-env.json was written by a pre-v0.7 preflight (envSchema=$envSchema; legacy keys: $($legacyKeys -join ',')). Re-run codex-preflight.ps1."
}
if ($Effort -eq 'ultra' -and $NoUltraModels -contains $Model) {
    $warnings += "$Model has no 'ultra' effort; clamped to 'max'."
    $Effort = 'max'
}

# --json is what makes the run observable: progress events AND a turn.completed
# terminator. -o is what makes the answer readable without parsing anything.
$codexArgs = $inv.Prefix + @(
    'exec', '--json', '-',
    '-C', $WorkDir,
    '-s', $Sandbox,
    '-c', 'approval_policy=never',
    '-c', "model_reasoning_effort=$Effort",
    # The elevated Windows sandbox fails to start any shell on some machines
    # ("helper_unknown_error: setup refresh had errors"), so codex cannot read a
    # single file. Unelevated still enforces read-only (measured: writes denied).
    '-c', 'windows.sandbox=unelevated',
    '--skip-git-repo-check',
    '-o', $lastFile
)
if ($Model) { $codexArgs += @('-m', $Model) }
# Measured: -c plugins."superpowers@...".enabled=false does NOT hide the skills;
# only turning the plugins feature off does.
if (-not $KeepPlugins) { $codexArgs += @('--disable', 'plugins') }
foreach ($d in $AddDir) {
    if ($d) {
        if (-not (Test-Path -LiteralPath $d)) { throw "AddDir does not exist: $d" }
        $codexArgs += @('--add-dir', (Resolve-Path -LiteralPath $d).Path)
    }
}

$argLine = ConvertTo-ArgLine $codexArgs
$codexHome = ''
if ($codexEnv.PSObject.Properties.Name -contains 'codexHome') { $codexHome = [string]$codexEnv.codexHome }
$jobFile = Join-Path $RunDir "$Label.job.json"
$job = [ordered]@{
    label          = $Label
    runDir         = $RunDir
    file           = $inv.File
    argLine        = $argLine
    promptFile     = $normalizedPrompt
    outFile        = $outFile
    errFile        = $errFile
    codexHome      = $codexHome
    timeoutMinutes = $TimeoutMinutes
}
Write-TextFile $jobFile ($job | ConvertTo-Json -Depth 4)

$hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $hostExe)) {
    $gcHost = Get-Command powershell -ErrorAction SilentlyContinue
    if (-not $gcHost) { $gcHost = Get-Command pwsh -ErrorAction SilentlyContinue }
    if (-not $gcHost) { throw 'no PowerShell host found to run the worker' }
    $hostExe = $gcHost.Source
}
$workerArgLine = ConvertTo-ArgLine @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', $PSCommandPath, '-Worker', '-JobFile', $jobFile,
    # -File binds every declared Mandatory parameter, so satisfy them.
    '-EnvFile', $EnvFile, '-Label', $Label, '-PromptFile', $normalizedPrompt, '-WorkDir', $WorkDir, '-Role', $Role
)

# Win32_Process.Create parents the worker to WmiPrvSE instead of this shell, so a
# session-tree kill at a turn boundary does not take the delegation with it.
# Start-Process is the fallback when WMI is unavailable.
$workerPid = 0
$spawn = 'wmi'
try {
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine      = ('"{0}" {1}' -f $hostExe, $workerArgLine)
        CurrentDirectory = $RunDir
    } -ErrorAction Stop
    if ($r.ReturnValue -eq 0 -and $r.ProcessId -gt 0) { $workerPid = [int]$r.ProcessId }
} catch { }
if ($workerPid -le 0) {
    $spawn = 'start-process'
    $w = Start-Process -FilePath $hostExe -ArgumentList $workerArgLine -WindowStyle Hidden -PassThru
    $workerPid = $w.Id
}
Write-TextFile $pidFile ([string]$workerPid)

$meta = [ordered]@{
    label          = $Label
    workDir        = $WorkDir
    runDir         = $RunDir
    role           = $Role
    plugins        = $(if ($KeepPlugins) { 'enabled' } else { 'disabled' })
    model          = $Model
    effort         = $Effort
    sandbox        = $Sandbox
    codexHome      = $codexHome
    outputSchema   = ''
    timeoutMinutes = $TimeoutMinutes
    workerPid      = $workerPid
    spawn          = $spawn
    codexVersion   = $codexEnv.version
    command        = ('{0} {1}' -f $inv.File, $argLine)
    startedAt      = (Get-Date).ToString('s')
}
Write-TextFile (Join-Path $RunDir "$Label.meta.json") ($meta | ConvertTo-Json -Depth 4)

Write-Kv 'RUN' 'STARTED'
Write-Kv 'LABEL' $Label
Write-Kv 'RUN_DIR' $RunDir
Write-Kv 'WORKER_PID' $workerPid
Write-Kv 'SPAWN' $spawn
Write-Kv 'ROLE' $Role
Write-Kv 'MODEL' $Model
Write-Kv 'EFFORT' $Effort
Write-Kv 'SANDBOX' $Sandbox
foreach ($w in $warnings) { Write-Kv 'WARN' $w }
Write-Kv 'TIMEOUT_MIN' $TimeoutMinutes
Write-Kv 'NEXT' ("powershell -NoProfile -File '{0}\codex-status.ps1' -RunDir '{1}' -Label '{2}' -WaitMinutes 9" -f $PSScriptRoot, $RunDir, $Label)
exit 0
