param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$ApiBaseUrl,

    [ValidateRange(75497472, 201326592)]
    [long]$TargetBytes = 75497472,

    [switch]$ProvisionFreshTriggerSecret
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$triggerSecret = $env:WORKER_TRIGGER_SECRET
$secretBytes = $null
if ($ProvisionFreshTriggerSecret) {
    $secretBytes = New-Object byte[] 32
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($secretBytes)
        $triggerSecret = [Convert]::ToBase64String($secretBytes)
    } finally {
        $random.Dispose()
    }

    $triggerSecret |
        npx --yes vercel@58.1.0 -- env add `
            WORKER_TRIGGER_SECRET 'production,preview' `
            --project health-tracking-api-staging `
            --scope phukaokks-projects `
            --force `
            --sensitive `
            --yes
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to rotate the encrypted staging worker trigger.'
    }

    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Push-Location $repositoryRoot
    try {
        npx --yes vercel@58.1.0 -- deploy . `
            --prod `
            --yes `
            --project health-tracking-api-staging `
            --scope phukaokks-projects
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to redeploy the staging API after trigger rotation.'
        }
    } finally {
        Pop-Location
    }
}

if ([string]::IsNullOrWhiteSpace($triggerSecret)) {
    throw 'WORKER_TRIGGER_SECRET is not available in the staging process environment.'
}

$headers = @{
    'X-Worker-Trigger' = $triggerSecret
}
$triggerUri = $ApiBaseUrl.TrimEnd('/') + '/api/v1/worker/trigger'

$processImportStatus = 0
try {
    Invoke-WebRequest `
        -Method Post `
        -Uri $triggerUri `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body '{"mode":"process_import"}' `
        -UseBasicParsing | Out-Null
} catch {
    if ($null -eq $_.Exception.Response) {
        throw
    }
    $processImportStatus = [int]$_.Exception.Response.StatusCode
}

if ($processImportStatus -ne 400) {
    throw "Expected the real-import feature gate to return 400; received $processImportStatus."
}

$singleBody = @{
    mode = 'synthetic_benchmark'
    target_bytes = $TargetBytes
} | ConvertTo-Json -Compress

$singleResponse = Invoke-RestMethod `
    -Method Post `
    -Uri $triggerUri `
    -Headers $headers `
    -ContentType 'application/json' `
    -Body $singleBody `
    -TimeoutSec 250

$multiBody = @{
    mode = 'synthetic_multifile_benchmark'
    target_bytes = 346030080
} | ConvertTo-Json -Compress

$multiResponse = Invoke-RestMethod `
    -Method Post `
    -Uri $triggerUri `
    -Headers $headers `
    -ContentType 'application/json' `
    -Body $multiBody `
    -TimeoutSec 250

$evidence = [pscustomobject]@{
    process_import_gate_status = $processImportStatus
    single_file = [pscustomobject]@{
        status = $singleResponse.status
        mode = $singleResponse.mode
        worker_authenticated = [bool]$singleResponse.worker_authenticated
        parser_version = $singleResponse.benchmark.parser_version
        file_count = [int]$singleResponse.benchmark.file_count
        input_bytes = [long]$singleResponse.benchmark.input_bytes
        normalized_record_count = [int]$singleResponse.benchmark.normalized_record_count
        batch_count = [int]$singleResponse.benchmark.batch_count
        resumed_from_batch = [int]$singleResponse.benchmark.resumed_from_batch
        deterministic_recovery = [bool]$singleResponse.benchmark.deterministic_recovery
        warning_count = [int]$singleResponse.benchmark.warning_count
        duration_ms = [long]$singleResponse.benchmark.duration_ms
        heap_inuse_bytes = [long]$singleResponse.benchmark.heap_inuse_bytes
    }
    multi_file = [pscustomobject]@{
        status = $multiResponse.status
        mode = $multiResponse.mode
        worker_authenticated = [bool]$multiResponse.worker_authenticated
        parser_version = $multiResponse.benchmark.parser_version
        file_count = [int]$multiResponse.benchmark.file_count
        input_bytes = [long]$multiResponse.benchmark.input_bytes
        normalized_record_count = [int]$multiResponse.benchmark.normalized_record_count
        batch_count = [int]$multiResponse.benchmark.batch_count
        resumed_from_batch = [int]$multiResponse.benchmark.resumed_from_batch
        deterministic_recovery = [bool]$multiResponse.benchmark.deterministic_recovery
        warning_count = [int]$multiResponse.benchmark.warning_count
        duration_ms = [long]$multiResponse.benchmark.duration_ms
        heap_inuse_bytes = [long]$multiResponse.benchmark.heap_inuse_bytes
    }
}

if (
    $evidence.single_file.status -ne 'ok' -or
    $evidence.single_file.mode -ne 'synthetic_benchmark' -or
    -not $evidence.single_file.worker_authenticated -or
    $evidence.single_file.file_count -ne 1 -or
    -not $evidence.single_file.deterministic_recovery -or
    $evidence.single_file.input_bytes -ne $TargetBytes -or
    $evidence.single_file.duration_ms -ge 180000 -or
    $evidence.single_file.heap_inuse_bytes -ge 201326592 -or
    $evidence.multi_file.status -ne 'ok' -or
    $evidence.multi_file.mode -ne 'synthetic_multifile_benchmark' -or
    -not $evidence.multi_file.worker_authenticated -or
    $evidence.multi_file.file_count -ne 5 -or
    -not $evidence.multi_file.deterministic_recovery -or
    $evidence.multi_file.input_bytes -ne 346030080 -or
    $evidence.multi_file.duration_ms -ge 180000 -or
    $evidence.multi_file.heap_inuse_bytes -ge 201326592
) {
    throw ('The hosted worker benchmark did not meet the Step 4 acceptance gates: ' + ($evidence | ConvertTo-Json -Compress))
}

$evidence | ConvertTo-Json

$triggerSecret = $null
if ($null -ne $secretBytes) {
    [Array]::Clear($secretBytes, 0, $secretBytes.Length)
}
