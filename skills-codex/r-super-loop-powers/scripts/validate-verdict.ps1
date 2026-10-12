[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('gate', 'escalation')]
    [string]$Kind,

    [Parameter(Mandatory)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-NoDuplicateJsonProperty {
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement]$Element
    )

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $propertyNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $propertyNames.Add($property.Name)) {
                throw "Duplicate JSON property '$($property.Name)' is not allowed."
            }
            Assert-NoDuplicateJsonProperty -Element $property.Value
        }
        return
    }

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) {
            Assert-NoDuplicateJsonProperty -Element $item
        }
    }
}

function Assert-Blank {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$FieldName
    )

    if ($Value.Length -ne 0) {
        throw "$FieldName must be an empty string."
    }
}

function Assert-NonBlank {
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$FieldName
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$FieldName must be nonblank."
    }
}

function Assert-EmptyArray {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Value,

        [Parameter(Mandatory)]
        [string]$FieldName
    )

    if ($Value.Count -ne 0) {
        throw "$FieldName must be empty."
    }
}

function Assert-NonBlankArrayEntries {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Value,

        [Parameter(Mandatory)]
        [string]$FieldName
    )

    foreach ($entry in $Value) {
        if ([string]::IsNullOrWhiteSpace([string]$entry)) {
            throw "$FieldName entries must be nonblank."
        }
    }
}

function Assert-GateSemantics {
    param(
        [Parameter(Mandatory)]
        [Collections.IDictionary]$Verdict
    )

    Assert-NonBlank -Value $Verdict.rationale -FieldName 'rationale'
    $rationaleLineCount = ($Verdict.rationale -split '\r\n|\n|\r').Count
    if ($rationaleLineCount -gt 5) {
        throw 'rationale must contain no more than five lines.'
    }

    switch ($Verdict.verdict) {
        'PASS' {
            Assert-Blank -Value $Verdict.return_to -FieldName 'return_to for PASS'
            Assert-EmptyArray -Value $Verdict.target_unknowns -FieldName 'target_unknowns for PASS'
            Assert-EmptyArray -Value $Verdict.blocking_questions -FieldName 'blocking_questions for PASS'
        }
        { $_ -in 'REVISE', 'REPLAN' } {
            Assert-NonBlank -Value $Verdict.return_to -FieldName "return_to for $($Verdict.verdict)"
            Assert-NonBlankArrayEntries -Value $Verdict.target_unknowns -FieldName 'target_unknowns'
            Assert-EmptyArray -Value $Verdict.blocking_questions -FieldName "blocking_questions for $($Verdict.verdict)"
        }
        'BLOCKED' {
            Assert-Blank -Value $Verdict.return_to -FieldName 'return_to for BLOCKED'
            Assert-EmptyArray -Value $Verdict.target_unknowns -FieldName 'target_unknowns for BLOCKED'
            if ($Verdict.blocking_questions.Count -eq 0) {
                throw 'blocking_questions for BLOCKED must contain at least one question.'
            }
            Assert-NonBlankArrayEntries -Value $Verdict.blocking_questions -FieldName 'blocking_questions'
        }
        default {
            throw "Unsupported gate verdict '$($Verdict.verdict)'."
        }
    }
}

function Assert-EscalationSemantics {
    param(
        [Parameter(Mandatory)]
        [Collections.IDictionary]$Verdict
    )

    Assert-NonBlank -Value $Verdict.rationale -FieldName 'rationale'

    switch ($Verdict.decision) {
        'DECIDE' {
            Assert-NonBlank -Value $Verdict.judgement -FieldName 'judgement for DECIDE'
            Assert-Blank -Value $Verdict.question_for_human -FieldName 'question_for_human for DECIDE'
        }
        'ASK_HUMAN' {
            Assert-Blank -Value $Verdict.judgement -FieldName 'judgement for ASK_HUMAN'
            Assert-NonBlank -Value $Verdict.question_for_human -FieldName 'question_for_human for ASK_HUMAN'
        }
        default {
            throw "Unsupported escalation decision '$($Verdict.decision)'."
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Response file does not exist: $Path"
    }

    $schemaPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\schemas\$Kind-verdict.json"))
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
        throw "Schema file does not exist: $schemaPath"
    }

    $responsePath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $rawJson = [IO.File]::ReadAllText($responsePath, [Text.Encoding]::UTF8)

    $jsonDocument = $null
    try {
        $jsonDocument = [System.Text.Json.JsonDocument]::Parse($rawJson)
        Assert-NoDuplicateJsonProperty -Element $jsonDocument.RootElement
    } finally {
        if ($null -ne $jsonDocument) {
            $jsonDocument.Dispose()
        }
    }

    $schemaValid = Test-Json -Json $rawJson -SchemaFile $schemaPath -ErrorAction Stop
    if ($schemaValid -ne $true) {
        throw "Response JSON does not satisfy the $Kind verdict schema."
    }

    $verdict = ConvertFrom-Json -InputObject $rawJson -AsHashtable -Depth 100 -ErrorAction Stop
    if ($Kind -eq 'gate') {
        Assert-GateSemantics -Verdict $verdict
    } else {
        Assert-EscalationSemantics -Verdict $verdict
    }

    Write-Output 'Validation OK'
    exit 0
} catch {
    Write-Error "Validation failed: $($_.Exception.Message)"
    exit 1
}
