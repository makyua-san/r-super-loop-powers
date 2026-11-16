#Requires -Version 5.1
<#
  parallel.ps1 -- two milestones in two git worktrees, one ledger in the git common dir.
    -Prepare -Milestones "1-foo,2-bar"   split the base into two child worktrees
    -Status                              show the group as seen from the calling work tree
    -Pass / -Halt / -Merge / -Cleanup    (later tasks)
  Ledger: <git common dir>\rslp-parallel\<goal-slug>\ (group.json, m<n>.json, merger, halt.json).
  Branches rslp/<slug>/m<n>; worktrees <WorktreeRoot>\<slug>-m<n>.
  stdout is ASCII "KEY: value"; STATUS is OK / REFUSED / FAILED / CONFLICT / HALTED, and
  anything but OK exits 1. REFUSED and FAILED leave nothing behind.
  Saved as UTF-8 with BOM: the state.md keys and the wait text are Japanese.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GoalDir,   # the goal dir in the calling work tree
    [switch]$Prepare, [switch]$Status, [switch]$Pass, [switch]$Merge, [switch]$Halt, [switch]$Cleanup,
    [string]$Milestones = '',      # -Prepare: "1-foo,2-bar" (exactly two)
    [string]$WorktreeRoot = '',    # -Prepare: default <base parent>\<base folder name>.rslp
    [string]$Reason = '',          # -Halt
    [string]$Keep = '',            # -Halt: milestone number to keep (default: the calling child)
    [int]$ElectTries = 5,          # -Pass: election attempts
    [int]$ElectWaitMs = 1000       # -Pass: wait between attempts
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
. (Join-Path $PSScriptRoot 'codex-common.ps1')

# stdout stays ASCII (console code pages differ between hosts).
function ConvertTo-Ascii([string]$Text) { return ($Text -replace '[^\x00-\x7F]', '?') }

function Stop-Failed([string]$Reason, [string]$Next) {
    Write-Kv 'STATUS' 'FAILED'
    Write-Kv 'REASON' (ConvertTo-Ascii $Reason)
    if ($Next) { Write-Kv 'NEXT' (ConvertTo-Ascii $Next) }
    exit 1
}

function Stop-Refused([string]$Reason, [string]$Next) {
    Write-Kv 'STATUS' 'REFUSED'
    Write-Kv 'REASON' (ConvertTo-Ascii $Reason)
    if ($Next) { Write-Kv 'NEXT' (ConvertTo-Ascii $Next) }
    exit 1
}

# git -C <dir> ... with stderr folded in. Native stderr under 'Stop' would throw
# (e.g. "Preparing worktree"), so the call runs under 'Continue' and is judged by exit code.
function Invoke-Git([string]$Dir, [string[]]$GitArgs) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & git -C $Dir @GitArgs 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    # Not Trim(): porcelain lines start with a space (" M app.txt").
    return @{ Out = (@($lines) -join "`n").TrimEnd().TrimStart("`r", "`n"); Code = $code }
}

# loop-log.ps1 as a child process (same launch as loop-log.ps1 uses for resume-packet.ps1).
function Invoke-LoopLog([string[]]$LogArgs) {
    $logScript = Join-Path $PSScriptRoot 'loop-log.ps1'
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = 'powershell' }
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $logScript @LogArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    return @{ Out = $out; Code = $code }
}

function Get-OutKv([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Key) + ': ?([^\r\n]*)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Get-Field([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^[ \t]*-[ \t]*' + [regex]::Escape($Key) + ':[ \t]*([^\r\n]*)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

# git hands back "/" paths; the ledger, state.md and stdout use "\".
function ConvertTo-WinPath([string]$Path) { return $Path.Replace('/', '\') }
# Comparison key: separators, a trailing separator and case do not matter.
function Get-PathKey([string]$Path) { return $Path.Replace('/', '\').TrimEnd('\').ToLowerInvariant() }

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $text = Read-TextFile $Path
    if (-not $text.Trim()) { return $null }
    return ($text | ConvertFrom-Json)
}

# The ledger as seen from the work tree that holds $GoalDir.
function Get-Ledger([string]$GoalDir) {
    $topR = Invoke-Git $GoalDir @('rev-parse', '--show-toplevel')
    if ($topR.Code -ne 0) { Stop-Failed "not inside a git work tree: $GoalDir" '' }
    $top = ConvertTo-WinPath $topR.Out
    $cdR = Invoke-Git $GoalDir @('rev-parse', '--path-format=absolute', '--git-common-dir')
    if ($cdR.Code -ne 0) { Stop-Failed ('git common dir not found: ' + $cdR.Out) '' }
    $topKey = Get-PathKey $top
    $goalKey = Get-PathKey $GoalDir
    if ($goalKey -ne $topKey -and -not $goalKey.StartsWith($topKey + '\')) { Stop-Failed "GoalDir is not inside the work tree $top" '' }
    $goalRel = $GoalDir.Replace('/', '\').TrimEnd('\').Substring($topKey.Length).TrimStart('\').Replace('\', '/')
    $dir = Join-Path (ConvertTo-WinPath $cdR.Out) ('rslp-parallel\' + (Split-Path -Leaf $GoalDir))

    $group = Read-JsonFile (Join-Path $dir 'group.json')
    $rows = @{}
    if (Test-Path -LiteralPath $dir -PathType Container) {
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File)) {
            if ($f.Name -match '^m(\d+)\.json$') { $rows[$Matches[1]] = Read-JsonFile $f.FullName }
        }
    }
    $haltRow = Read-JsonFile (Join-Path $dir 'halt.json')
    $merger = $null
    $mergerFile = Join-Path $dir 'merger'
    if (Test-Path -LiteralPath $mergerFile -PathType Leaf) { $merger = (Read-TextFile $mergerFile).Trim() }

    $role = 'none'
    $self = $null
    if ($null -ne $group) {
        if ((Get-PathKey ([string]$group.base)) -eq $topKey) { $role = 'base' }
        else {
            foreach ($m in @($group.milestones)) {
                if ((Get-PathKey ([string]$m.worktree)) -eq $topKey) { $role = 'child'; $self = [string]$m.n }
            }
        }
    }
    return @{ Dir = $dir; Group = $group; Rows = $rows; Halt = $haltRow; Merger = $merger; Self = $self; Role = $role; Top = $top; GoalRel = $goalRel }
}

function Invoke-Status {
    $L = Get-Ledger $GoalDir
    if ($null -eq $L.Group) {
        Write-Kv 'GROUP' 'none'
        Write-Kv 'STATUS' 'OK'
        exit 0
    }
    $ms = @($L.Group.milestones)
    Write-Kv 'GROUP' (ConvertTo-Ascii ((@($ms | ForEach-Object { [string]$_.name })) -join ' + '))
    Write-Kv 'ROLE' $L.Role
    if ($L.Role -eq 'child') { Write-Kv 'SELF' ('m' + $L.Self) }
    Write-Kv 'BASE' (ConvertTo-Ascii ([string]$L.Group.base))
    foreach ($m in $ms) {
        $n = [string]$m.n
        $row = $L.Rows[$n]
        $st = '-'; $sha = '-'
        if ($null -ne $row) {
            if ($row.status) { $st = [string]$row.status }
            if ($row.sha) { $sha = [string]$row.sha }
        }
        Write-Kv 'CHILD' (ConvertTo-Ascii ('m{0} | {1} | {2} | {3}' -f $n, $st, $sha, [string]$m.worktree))
    }
    if ($L.Merger) { Write-Kv 'MERGER' $L.Merger } else { Write-Kv 'MERGER' '-' }
    if ($null -ne $L.Halt) { Write-Kv 'HALTED' (ConvertTo-Ascii ('yes | keep=m{0} | {1}' -f [string]$L.Halt.keep, [string]$L.Halt.reason)) }
    else { Write-Kv 'HALTED' 'no' }
    if ($L.Group.merged) { Write-Kv 'MERGED' ([string]$L.Group.merged) } else { Write-Kv 'MERGED' '-' }
    Write-Kv 'STATUS' 'OK'
    exit 0
}

# "- parallel-base: <base>" just before "- updated:", with that line's line ending.
function Add-ParallelBase([string]$Text, [string]$Base) {
    $pb = [regex]::Match($Text, '(?m)^([ \t]*-[ \t]*parallel-base:)[ \t]*[^\r\n]*')
    if ($pb.Success) { return $Text.Substring(0, $pb.Index) + $pb.Groups[1].Value + ' ' + $Base + $Text.Substring($pb.Index + $pb.Length) }
    $u = [regex]::Match($Text, '(?m)^[ \t]*-[ \t]*updated:[^\r\n]*(\r?\n)?')
    if (-not $u.Success) { return $null }
    $nl = $u.Groups[1].Value
    if (-not $nl) { if ($Text.Contains("`r`n")) { $nl = "`r`n" } else { $nl = "`n" } }
    return $Text.Insert($u.Index, "- parallel-base: $Base$nl")
}

function Invoke-Prepare {
    # --- checks: any hit -> REFUSED, nothing written ---
    $names = @($Milestones -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($names.Count -ne 2) { Stop-Refused "-Milestones needs exactly two names (got $($names.Count))" 'pass -Milestones "<n>-<name>,<n>-<name>"' }
    $items = @()
    foreach ($name in $names) {
        if ($name -notmatch '^(\d+)-') { Stop-Refused "milestone name must start with '<number>-': $name" '' }
        $items += @{ n = $Matches[1]; name = $name }
    }
    if ($items[0].n -eq $items[1].n) { Stop-Refused "both milestones have number $($items[0].n)" 'pass two milestones with different numbers' }

    $stateFile = Join-Path $GoalDir 'state.md'
    $stateText = Read-TextFile $stateFile
    if (-not $stateText.Trim()) { Stop-Failed "state.md not found or empty: $stateFile" '' }
    if (-not (Get-Field $stateText '強度').StartsWith('MVP')) { Stop-Refused 'parallel milestones need MVP intensity; state.md has another intensity' 'run the milestones one after another' }

    $L = Get-Ledger $GoalDir
    $top = $L.Top
    $br = Invoke-Git $top @('symbolic-ref', '--short', '-q', 'HEAD')
    if ($br.Code -ne 0 -or -not $br.Out) { Stop-Refused 'the base is on a detached HEAD' 'check out a branch, then run again' }
    $baseBranch = $br.Out
    $dirty = Invoke-Git $top @('status', '--porcelain', '--untracked-files=no')
    if ($dirty.Code -ne 0) { Stop-Failed ('git status failed: ' + $dirty.Out) '' }
    if ($dirty.Out) {
        $paths = @($dirty.Out -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_.Substring([Math]::Min(3, $_.Length)) } | Select-Object -First 10)
        Stop-Refused ('uncommitted changes: ' + ($paths -join ', ')) 'commit (or stash) them, then run again'
    }
    $spec = $L.GoalRel
    if (-not $spec) { $spec = '.' }
    $un = Invoke-Git $top @('ls-files', '--others', '--exclude-standard', '--', $spec)
    if ($un.Code -ne 0) { Stop-Failed ('git ls-files failed: ' + $un.Out) '' }
    $skip = @('resume-pending', 'resume-packet.md', 'resume-pending.failed')
    $untracked = @($un.Out -split "`n" | Where-Object { $_.Trim() } | Where-Object { $skip -notcontains (($_.Trim('"')) -split '/')[-1] })
    if ($untracked.Count -gt 0) {
        Stop-Refused ('untracked files in the goal folder: ' + ((@($untracked | Select-Object -First 10)) -join ', ')) 'commit them, then run again'
    }

    $slug = Split-Path -Leaf $GoalDir
    if ($WorktreeRoot) {
        $wtRoot = $WorktreeRoot
        if (-not [IO.Path]::IsPathRooted($wtRoot)) { $wtRoot = Join-Path (Get-Location).Path $wtRoot }
        $wtRoot = [IO.Path]::GetFullPath($wtRoot).TrimEnd('\')
    } else {
        $wtRoot = Join-Path (Split-Path -Parent $top) ((Split-Path -Leaf $top) + '.rslp')
    }
    foreach ($it in $items) {
        $it.branch = "rslp/$slug/m$($it.n)"
        $it.worktree = Join-Path $wtRoot "$slug-m$($it.n)"
    }
    if (Test-Path -LiteralPath $L.Dir) { Stop-Refused "a parallel group already exists for this goal: $($L.Dir)" "run parallel.ps1 -GoalDir `"$GoalDir`" -Status" }
    foreach ($it in $items) {
        if ((Invoke-Git $top @('show-ref', '--verify', '--quiet', "refs/heads/$($it.branch)")).Code -eq 0) { Stop-Refused "branch already exists: $($it.branch)" 'delete it (or finish the earlier group), then run again' }
        if (Test-Path -LiteralPath $it.worktree) { Stop-Refused "worktree path already exists: $($it.worktree)" 'remove it (or pass -WorktreeRoot), then run again' }
    }
    $shaR = Invoke-Git $top @('rev-parse', 'HEAD')
    if ($shaR.Code -ne 0) { Stop-Failed ('git rev-parse HEAD failed: ' + $shaR.Out) '' }

    # --- 1. base state.md (the design.md gate lives in loop-log) ---
    $stateBytes = [IO.File]::ReadAllBytes($stateFile)
    $a = $items[0].name; $b = $items[1].name
    $ll = Invoke-LoopLog @('-GoalDir', $GoalDir, '-SetPhase', 'parallel', '-SetMilestone', "$a + $b", '-SetWait', "並行中: $a / $b(合流まで、このフォルダでは作業しない)")
    if ($ll.Code -ne 0) {
        if ((Get-OutKv $ll.Out 'STATUS') -eq 'REFUSED') { Stop-Refused (Get-OutKv $ll.Out 'REASON') (Get-OutKv $ll.Out 'NEXT') }
        Stop-Failed ('loop-log.ps1 failed on the base: ' + (Get-OutKv $ll.Out 'REASON')) (Get-OutKv $ll.Out 'NEXT')
    }

    $commonDir = Split-Path -Parent (Split-Path -Parent $L.Dir)
    $attrFile = Join-Path $commonDir 'info\attributes'
    $attrBytes = $null
    if (Test-Path -LiteralPath $attrFile -PathType Leaf) { $attrBytes = [IO.File]::ReadAllBytes($attrFile) }
    $wtRootExisted = Test-Path -LiteralPath $wtRoot
    try {
        # --- 2. union merge for the append-only logs ---
        $want = @('docs/r-super-loop-powers/*/assumptions.md merge=union', 'docs/r-super-loop-powers/*/call-log.md merge=union',
            'docs/r-super-loop-powers/*/hook-log.md merge=union', 'docs/r-super-loop-powers/*/scout/index.md merge=union')
        $attrText = Read-TextFile $attrFile
        $have = @($attrText -split "`r?`n" | ForEach-Object { $_.Trim() })
        $add = @($want | Where-Object { $have -notcontains $_ })
        if ($add.Count -gt 0) {
            $nl = "`n"
            if ($attrText.Contains("`r`n")) { $nl = "`r`n" }
            if ($attrText -and -not $attrText.EndsWith("`n")) { $attrText += $nl }
            $infoDir = Split-Path -Parent $attrFile
            if (-not (Test-Path -LiteralPath $infoDir)) { New-Item -ItemType Directory -Path $infoDir -Force | Out-Null }
            Write-TextFile $attrFile ($attrText + ($add -join $nl) + $nl)
        }

        # --- 3. worktrees ---
        foreach ($it in $items) {
            $r = Invoke-Git $top @('worktree', 'add', '-q', '-b', $it.branch, $it.worktree, 'HEAD')
            if ($r.Code -ne 0) { throw "git worktree add failed for m$($it.n): $($r.Out)" }
        }

        # --- 4. child state.md: parallel-base line, then the milestone fields and the resume marker ---
        foreach ($it in $items) {
            $childGoal = Join-Path $it.worktree ($L.GoalRel.Replace('/', '\'))
            $childState = Join-Path $childGoal 'state.md'
            $newText = Add-ParallelBase (Read-TextFile $childState) $top
            if ($null -eq $newText) { throw "state.md in m$($it.n) has no '- updated:' line" }
            Write-TextFile $childState $newText
            $cl = Invoke-LoopLog @('-GoalDir', $childGoal, '-SetPhase', 'milestone-implementation', '-SetMilestone', $it.name,
                '-SetOwner', 'opus-main', '-SetGate', 'impl-gate', '-Clear', '待ち,codex-run', '-Mark')
            if ($cl.Code -ne 0) { throw ("loop-log.ps1 failed in m$($it.n): " + (Get-OutKv $cl.Out 'STATUS') + ' ' + (Get-OutKv $cl.Out 'REASON')) }
        }

        # --- 5. ledger (group.json last: its presence means the split is complete) ---
        New-Item -ItemType Directory -Path $L.Dir -Force | Out-Null
        $now = (Get-Date).ToString('o')
        foreach ($it in $items) {
            $row = [ordered]@{ n = [string]$it.n; status = 'running'; started = $now; passed = $null; sha = $null }
            Write-ExitFile (Join-Path $L.Dir "m$($it.n).json") ($row | ConvertTo-Json)
        }
        $msList = @()
        foreach ($it in $items) { $msList += [ordered]@{ n = [string]$it.n; name = $it.name; branch = $it.branch; worktree = $it.worktree } }
        $group = [ordered]@{
            slug = $slug; base = $top; baseBranch = $baseBranch; baseSha = $shaR.Out; created = $now
            milestones = $msList; merged = $null; conflicts = @(); redo = @()
        }
        Write-ExitFile (Join-Path $L.Dir 'group.json') ($group | ConvertTo-Json -Depth 5)
    } catch {
        $why = $_.Exception.Message
        # --- 6. roll back everything steps 1-5 made ---
        foreach ($it in $items) {
            if (Test-Path -LiteralPath $it.worktree) {
                $null = Invoke-Git $top @('worktree', 'remove', '--force', $it.worktree)
                if (Test-Path -LiteralPath $it.worktree) { Remove-Item -LiteralPath $it.worktree -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
        $null = Invoke-Git $top @('worktree', 'prune')
        foreach ($it in $items) { $null = Invoke-Git $top @('branch', '-D', $it.branch) }
        if (-not $wtRootExisted -and (Test-Path -LiteralPath $wtRoot) -and -not (Get-ChildItem -LiteralPath $wtRoot -Force)) {
            Remove-Item -LiteralPath $wtRoot -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $L.Dir) { Remove-Item -LiteralPath $L.Dir -Recurse -Force -ErrorAction SilentlyContinue }
        if ($null -ne $attrBytes) { [IO.File]::WriteAllBytes($attrFile, $attrBytes) }
        elseif (Test-Path -LiteralPath $attrFile) { Remove-Item -LiteralPath $attrFile -Force -ErrorAction SilentlyContinue }
        [IO.File]::WriteAllBytes($stateFile, $stateBytes)
        Write-Kv 'STATUS' 'FAILED'
        Write-Kv 'REASON' (ConvertTo-Ascii $why)
        Write-Kv 'ROLLED_BACK' 'yes'
        Write-Kv 'NEXT' 'fix the cause, then run -Prepare again'
        exit 1
    }

    foreach ($it in $items) { Write-Kv 'WORKTREE' (ConvertTo-Ascii "m$($it.n) | $($it.worktree)") }
    foreach ($it in $items) { Write-Kv 'BRANCH' (ConvertTo-Ascii "m$($it.n) | $($it.branch)") }
    Write-Kv 'LEDGER' (ConvertTo-Ascii $L.Dir)
    Write-Kv 'STATUS' 'OK'
    Write-Kv 'NEXT' 'ask the human to open a new session in each WORKTREE folder and send "continue"; close this session'
    exit 0
}

# --- main ---
$modes = @()
foreach ($m in @('Prepare', 'Status', 'Pass', 'Merge', 'Halt', 'Cleanup')) { if ($PSBoundParameters.ContainsKey($m) -and $PSBoundParameters[$m]) { $modes += $m } }
if ($modes.Count -ne 1) { Stop-Failed 'pass exactly one of -Prepare / -Status / -Pass / -Merge / -Halt / -Cleanup' '' }
if (-not (Test-Path -LiteralPath $GoalDir -PathType Container)) { Stop-Failed "GoalDir does not exist: $GoalDir" '' }
$GoalDir = (Resolve-Path -LiteralPath $GoalDir).Path

switch ($modes[0]) {
    'Prepare' { Invoke-Prepare }
    'Status' { Invoke-Status }
    default { Stop-Failed 'not implemented' '' }
}
