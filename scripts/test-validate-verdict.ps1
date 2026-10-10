[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validatorPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\skills-codex\r-super-loop-powers\scripts\validate-verdict.ps1'))
$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase ("validate-verdict-tests-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
$tempRootFull = [IO.Path]::GetFullPath($tempRoot)

if (-not $tempRootFull.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -or
    -not (Split-Path -Leaf $tempRootFull).StartsWith('validate-verdict-tests-', [StringComparison]::Ordinal)) {
    throw "Refusing to use an unverified temporary directory: $tempRootFull"
}

$validGatePass = '{"verdict":"PASS","rationale":"All acceptance criteria are met.","return_to":"","target_unknowns":[],"blocking_questions":[]}'
$validGateRevise = '{"verdict":"REVISE","rationale":"One implementation detail needs correction.","return_to":"B-2 implementation","target_unknowns":["Confirm retry ownership"],"blocking_questions":[]}'
$validGateReplan = '{"verdict":"REPLAN","rationale":"The plan no longer covers the required boundary.","return_to":"A-4 plan","target_unknowns":[],"blocking_questions":[]}'
$validGateBlocked = '{"verdict":"BLOCKED","rationale":"A human-owned fact is unavailable.","return_to":"","target_unknowns":[],"blocking_questions":["Which production tenant should be used?"]}'
$validEscalationDecide = '{"decision":"DECIDE","judgement":"Use the documented default.","rationale":"The policy explicitly assigns this choice.","question_for_human":""}'
$validEscalationAsk = '{"decision":"ASK_HUMAN","judgement":"","rationale":"The choice changes customer-visible behavior.","question_for_human":"Which behavior should ship?"}'

$cases = @(
    [pscustomobject]@{ Name = 'accepts gate PASS'; Kind = 'gate'; Json = $validGatePass; Valid = $true }
    [pscustomobject]@{ Name = 'accepts gate REVISE with unknowns'; Kind = 'gate'; Json = $validGateRevise; Valid = $true }
    [pscustomobject]@{ Name = 'accepts gate REPLAN without unknowns'; Kind = 'gate'; Json = $validGateReplan; Valid = $true }
    [pscustomobject]@{ Name = 'accepts gate BLOCKED'; Kind = 'gate'; Json = $validGateBlocked; Valid = $true }
    [pscustomobject]@{ Name = 'accepts five-line gate rationale'; Kind = 'gate'; Json = '{"verdict":"PASS","rationale":"one\ntwo\nthree\nfour\nfive","return_to":"","target_unknowns":[],"blocking_questions":[]}'; Valid = $true }
    [pscustomobject]@{ Name = 'accepts escalation DECIDE'; Kind = 'escalation'; Json = $validEscalationDecide; Valid = $true }
    [pscustomobject]@{ Name = 'accepts escalation ASK_HUMAN'; Kind = 'escalation'; Json = $validEscalationAsk; Valid = $true }
    [pscustomobject]@{ Name = 'rejects malformed JSON'; Kind = 'gate'; Json = '{"verdict":'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects a fenced JSON response'; Kind = 'gate'; Json = "``````json`n$validGatePass`n``````"; Valid = $false }
    [pscustomobject]@{ Name = 'rejects prose before JSON'; Kind = 'gate'; Json = "Here is the verdict:`n$validGatePass"; Valid = $false }
    [pscustomobject]@{ Name = 'rejects a missing required key'; Kind = 'gate'; Json = '{"verdict":"PASS","rationale":"Complete.","return_to":"","target_unknowns":[]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects an extra key'; Kind = 'gate'; Json = '{"verdict":"PASS","rationale":"Complete.","return_to":"","target_unknowns":[],"blocking_questions":[],"extra":true}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects an unknown enum'; Kind = 'gate'; Json = '{"verdict":"APPROVE","rationale":"Complete.","return_to":"","target_unknowns":[],"blocking_questions":[]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects the wrong property type'; Kind = 'gate'; Json = '{"verdict":"PASS","rationale":"Complete.","return_to":"","target_unknowns":"none","blocking_questions":[]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects a duplicate top-level key'; Kind = 'gate'; Json = '{"verdict":"PASS","verdict":"BLOCKED","rationale":"Complete.","return_to":"","target_unknowns":[],"blocking_questions":[]}'; Valid = $false; ExpectedText = 'Duplicate JSON property' }
    [pscustomobject]@{ Name = 'rejects a duplicate key in a nested object'; Kind = 'gate'; Json = '{"verdict":"PASS","rationale":"Complete.","return_to":"","target_unknowns":[],"blocking_questions":[],"x":{"a":1,"a":2}}'; Valid = $false; ExpectedText = 'Duplicate JSON property' }
    [pscustomobject]@{ Name = 'rejects a missing response file'; Kind = 'gate'; Json = $null; Valid = $false; MissingFile = $true }
    [pscustomobject]@{ Name = 'rejects a missing shipped schema'; Kind = 'gate'; Json = $validGatePass; Valid = $false; MissingSchema = $true }
    [pscustomobject]@{ Name = 'rejects blank gate rationale'; Kind = 'gate'; Json = '{"verdict":"PASS","rationale":"   ","return_to":"","target_unknowns":[],"blocking_questions":[]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects a six-line gate rationale'; Kind = 'gate'; Json = '{"verdict":"PASS","rationale":"one\ntwo\nthree\nfour\nfive\nsix","return_to":"","target_unknowns":[],"blocking_questions":[]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects PASS with return_to'; Kind = 'gate'; Json = '{"verdict":"PASS","rationale":"Complete.","return_to":"B-2 implementation","target_unknowns":[],"blocking_questions":[]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects PASS with target_unknowns'; Kind = 'gate'; Json = '{"verdict":"PASS","rationale":"Complete.","return_to":"","target_unknowns":["Residual question"],"blocking_questions":[]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects PASS with blocking_questions'; Kind = 'gate'; Json = '{"verdict":"PASS","rationale":"Complete.","return_to":"","target_unknowns":[],"blocking_questions":["Why?"]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects REVISE with blank return_to'; Kind = 'gate'; Json = '{"verdict":"REVISE","rationale":"Needs correction.","return_to":"  ","target_unknowns":[],"blocking_questions":[]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects REPLAN with blocking questions'; Kind = 'gate'; Json = '{"verdict":"REPLAN","rationale":"Needs a new plan.","return_to":"A-4 plan","target_unknowns":[],"blocking_questions":["Choose?"]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects blank target unknown entries'; Kind = 'gate'; Json = '{"verdict":"REVISE","rationale":"Needs correction.","return_to":"B-2 implementation","target_unknowns":["  "],"blocking_questions":[]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects BLOCKED without questions'; Kind = 'gate'; Json = '{"verdict":"BLOCKED","rationale":"Cannot continue.","return_to":"","target_unknowns":[],"blocking_questions":[]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects BLOCKED with a blank question'; Kind = 'gate'; Json = '{"verdict":"BLOCKED","rationale":"Cannot continue.","return_to":"","target_unknowns":[],"blocking_questions":[" "]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects BLOCKED with return_to'; Kind = 'gate'; Json = '{"verdict":"BLOCKED","rationale":"Cannot continue.","return_to":"A-4 plan","target_unknowns":[],"blocking_questions":["Choose?"]}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects DECIDE with blank judgement'; Kind = 'escalation'; Json = '{"decision":"DECIDE","judgement":" ","rationale":"Policy applies.","question_for_human":""}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects DECIDE with blank rationale'; Kind = 'escalation'; Json = '{"decision":"DECIDE","judgement":"Use default.","rationale":"","question_for_human":""}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects DECIDE with a human question'; Kind = 'escalation'; Json = '{"decision":"DECIDE","judgement":"Use default.","rationale":"Policy applies.","question_for_human":"Confirm?"}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects ASK_HUMAN with judgement'; Kind = 'escalation'; Json = '{"decision":"ASK_HUMAN","judgement":"Use default.","rationale":"Human choice required.","question_for_human":"Which option?"}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects ASK_HUMAN with blank rationale'; Kind = 'escalation'; Json = '{"decision":"ASK_HUMAN","judgement":"","rationale":" ","question_for_human":"Which option?"}'; Valid = $false }
    [pscustomobject]@{ Name = 'rejects ASK_HUMAN with blank question'; Kind = 'escalation'; Json = '{"decision":"ASK_HUMAN","judgement":"","rationale":"Human choice required.","question_for_human":"  "}'; Valid = $false }
)

$passed = 0
$failed = 0
$caseIndex = 0

New-Item -ItemType Directory -Path $tempRootFull -ErrorAction Stop | Out-Null

try {
    foreach ($case in $cases) {
        $caseIndex++
        $caseDirectory = Join-Path $tempRootFull ("case-{0:D2}" -f $caseIndex)
        New-Item -ItemType Directory -Path $caseDirectory -ErrorAction Stop | Out-Null

        $responsePath = Join-Path $caseDirectory 'response.json'
        $missingFile = $case.PSObject.Properties.Name -contains 'MissingFile' -and $case.MissingFile
        if (-not $missingFile) {
            [IO.File]::WriteAllText($responsePath, [string]$case.Json, [Text.UTF8Encoding]::new($false))
        }

        $scriptToRun = $validatorPath
        $missingSchema = $case.PSObject.Properties.Name -contains 'MissingSchema' -and $case.MissingSchema
        if ($missingSchema) {
            $isolatedScripts = Join-Path $caseDirectory 'scripts'
            New-Item -ItemType Directory -Path $isolatedScripts -ErrorAction Stop | Out-Null
            $scriptToRun = Join-Path $isolatedScripts 'validate-verdict.ps1'
            if (Test-Path -LiteralPath $validatorPath -PathType Leaf) {
                Copy-Item -LiteralPath $validatorPath -Destination $scriptToRun -ErrorAction Stop
            }
        }

        $beforeBytes = if (Test-Path -LiteralPath $responsePath -PathType Leaf) {
            [IO.File]::ReadAllBytes($responsePath)
        } else {
            $null
        }

        $validatorAvailable = Test-Path -LiteralPath $scriptToRun -PathType Leaf
        if (-not $validatorAvailable) {
            $exitCode = -1
            $outputText = "Validator script does not exist: $scriptToRun"
        } else {
            $commandOutput = & $pwshPath -NoLogo -NoProfile -NonInteractive -File $scriptToRun -Kind $case.Kind -Path $responsePath 2>&1
            $exitCode = $LASTEXITCODE
            $outputText = ($commandOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        }

        $afterBytes = if (Test-Path -LiteralPath $responsePath -PathType Leaf) {
            [IO.File]::ReadAllBytes($responsePath)
        } else {
            $null
        }
        $inputUnchanged = if ($null -eq $beforeBytes -or $null -eq $afterBytes) {
            $null -eq $beforeBytes -and $null -eq $afterBytes
        } else {
            [Convert]::ToHexString($beforeBytes) -ceq [Convert]::ToHexString($afterBytes)
        }

        $outcomeCorrect = if (-not $validatorAvailable) {
            $false
        } elseif ($case.Valid) {
            $exitCode -eq 0 -and $outputText -match 'Validation OK'
        } else {
            $exitCode -ne 0 -and $outputText -notmatch 'Validation OK'
        }

        $expectedTextPresent = if ($case.PSObject.Properties.Name -contains 'ExpectedText') {
            $outputText -match [regex]::Escape([string]$case.ExpectedText)
        } else {
            $true
        }

        if ($outcomeCorrect -and $expectedTextPresent -and $inputUnchanged) {
            $passed++
            Write-Output "PASS: $($case.Name)"
        } else {
            $failed++
            Write-Output "FAIL: $($case.Name) (exit=$exitCode, expectedText=$expectedTextPresent, unchanged=$inputUnchanged)"
            if ($outputText) {
                Write-Output ("  " + ($outputText -replace "`r?`n", "`n  "))
            }
        }
    }
} finally {
    $cleanupTarget = [IO.Path]::GetFullPath($tempRootFull)
    if ($cleanupTarget.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $cleanupTarget).StartsWith('validate-verdict-tests-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $cleanupTarget -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning "Skipped cleanup of unverified path: $cleanupTarget"
    }
}

Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) {
    exit 1
}
exit 0
