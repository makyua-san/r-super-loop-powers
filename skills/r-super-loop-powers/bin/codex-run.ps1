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
    [string]$Model,
    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max', 'ultra')][string]$Effort = 'high',
    # Default comes from codex-env.json (what preflight proved actually works here).
    [ValidateSet('', 'read-only', 'workspace-write', 'danger-full-access')][string]$Sandbox = '',
    [string]$OutputSchema,
    [string[]]$AddDir = @(),
    # Extra sandbox writable roots. The working directory is always included when
    # preflight found that this machine needs them named explicitly.
    [string[]]$WritableRoot = @(),
    [int]$TimeoutMinutes = 60,
    [switch]$NoPreamble,
    # internal
    [switch]$Worker,
    [string]$JobFile
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'codex-common.ps1')

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
   read back. Put the complete self-verification report in the final message.
6. If you finish early because you are blocked, say so explicitly in the final
   message. Silence is read as a failed run, not as success.
== END EXECUTION CONTRACT ==

'@

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

# Take the sandbox preflight proved works here, unless the caller named one.
if (-not $Sandbox) {
    if ($codexEnv.PSObject.Properties.Name -contains 'sandbox' -and $codexEnv.sandbox) { $Sandbox = [string]$codexEnv.sandbox }
    else { $Sandbox = 'workspace-write' }
}

# Preflight already proved this machine cannot write under workspace-write. Launching
# anyway burns a full delegation that exits 0 having changed nothing -- refuse instead.
if ($Sandbox -eq 'workspace-write' -and $codexEnv.PSObject.Properties.Name -contains 'sandboxWriteOk' -and $codexEnv.sandboxWriteOk -eq $false) {
    throw "preflight found that -s workspace-write cannot write on this machine, so this delegation would do nothing. Re-run codex-preflight.ps1 with -AllowUnsandboxed once the human has approved running codex without its sandbox (policy.md negation list item 4), or re-run plain preflight if the environment changed."
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
$normalizedPrompt = Join-Path $RunDir "$Label.prompt.txt"
if ($NoPreamble) {
    Write-TextFile $normalizedPrompt $rawPrompt
} else {
    Write-TextFile $normalizedPrompt ($ExecutionContract + $rawPrompt)
}

$outFile = Join-Path $RunDir "$Label.out.jsonl"
$errFile = Join-Path $RunDir "$Label.err.txt"
$lastFile = Join-Path $RunDir "$Label.last.txt"
foreach ($stale in @($outFile, $errFile, $lastFile, $exitFile, (Join-Path $RunDir "$Label.done.json"))) {
    Remove-Item -LiteralPath $stale -Force -ErrorAction SilentlyContinue
}

if (-not $Model) { $Model = $codexEnv.model }

# --json is what makes the run observable: progress events AND a turn.completed
# terminator. -o is what makes the answer readable without parsing anything.
$codexArgs = $inv.Prefix + @(
    'exec', '--json', '-',
    '-C', $WorkDir,
    '-s', $Sandbox,
    '-c', 'approval_policy=never',
    '-c', "model_reasoning_effort=$Effort",
    '--skip-git-repo-check',
    '-o', $lastFile
)
if ($Model) { $codexArgs += @('-m', $Model) }
# Windows: the sandbox may be unable to infer its own writable root ("no writable
# root capability SIDs"), which rejects every shell command while the run still
# exits 0. preflight records whether naming them explicitly is required here.
$needRoots = $false
if ($codexEnv.PSObject.Properties.Name -contains 'writableRootsRequired' -and $codexEnv.writableRootsRequired) { $needRoots = $true }
if ($WritableRoot.Count -gt 0) { $needRoots = $true }
if ($Sandbox -eq 'workspace-write' -and $needRoots) {
    $roots = @($WorkDir)
    if ($codexEnv.PSObject.Properties.Name -contains 'writableRoots' -and $codexEnv.writableRoots) { $roots += @($codexEnv.writableRoots) }
    $roots += $WritableRoot
    $rootsArg = ConvertTo-WritableRootsArg $roots
    if ($rootsArg) { $codexArgs += @('-c', $rootsArg) }
}
foreach ($d in $AddDir) {
    if ($d) {
        if (-not (Test-Path -LiteralPath $d)) { throw "AddDir does not exist: $d" }
        $codexArgs += @('--add-dir', (Resolve-Path -LiteralPath $d).Path)
    }
}
if ($OutputSchema) {
    if (-not (Test-Path -LiteralPath $OutputSchema)) {
        # A missing schema path is not an error at the CLI boundary -- it hangs.
        throw "OutputSchema does not exist: $OutputSchema"
    }
    # Must be a native absolute path; a POSIX path makes the Windows binary hang.
    $codexArgs += @('--output-schema', (Resolve-Path -LiteralPath $OutputSchema).Path)
}

$argLine = ConvertTo-ArgLine $codexArgs
$jobFile = Join-Path $RunDir "$Label.job.json"
$job = [ordered]@{
    label          = $Label
    runDir         = $RunDir
    file           = $inv.File
    argLine        = $argLine
    promptFile     = $normalizedPrompt
    outFile        = $outFile
    errFile        = $errFile
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
    '-EnvFile', $EnvFile, '-Label', $Label, '-PromptFile', $normalizedPrompt, '-WorkDir', $WorkDir
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
    model          = $Model
    effort         = $Effort
    sandbox        = $Sandbox
    outputSchema   = $OutputSchema
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
Write-Kv 'MODEL' $Model
Write-Kv 'EFFORT' $Effort
Write-Kv 'SANDBOX' $Sandbox
if ($Sandbox -eq 'danger-full-access') {
    Write-Kv 'WARN' 'codex is running WITHOUT its sandbox: it can run any command and touch any path. Human-approved; the execution contract is the only thing keeping it in scope.'
}
Write-Kv 'TIMEOUT_MIN' $TimeoutMinutes
Write-Kv 'NEXT' ("powershell -NoProfile -File '{0}\codex-status.ps1' -RunDir '{1}' -Label '{2}' -WaitMinutes 9" -f $PSScriptRoot, $RunDir, $Label)
exit 0
