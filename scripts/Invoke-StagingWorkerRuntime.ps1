param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('process_import', 'cleanup_sources')]
    [string]$Mode,

    [ValidatePattern('^https://')]
    [string]$ApiBaseUrl = 'https://health-tracking-api-staging.vercel.app'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Deploy-StagingApi {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Push-Location $repositoryRoot
    try {
        npx --yes vercel@58.1.0 -- deploy . `
            --prod `
            --yes `
            --project health-tracking-api-staging `
            --scope phukaokks-projects
        if ($LASTEXITCODE -ne 0) {
            throw 'staging_api_deployment_failed'
        }
    } finally {
        Pop-Location
    }
}

function Set-ProcessImportGate([bool]$Enabled) {
    $value = if ($Enabled) { 'true' } else { 'false' }
    npx --yes vercel@58.1.0 -- env add `
        WORKER_PROCESS_IMPORT_ENABLED 'production,preview' `
        --value $value `
        --project health-tracking-api-staging `
        --scope phukaokks-projects `
        --force `
        --no-sensitive `
        --yes
    if ($LASTEXITCODE -ne 0) {
        throw 'staging_worker_gate_update_failed'
    }
}

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
    throw 'staging_worker_trigger_rotation_failed'
}

$evidence = $null
$restoreError = $null
try {
    Set-ProcessImportGate $true
    Deploy-StagingApi

    $headers = @{ 'X-Worker-Trigger' = $triggerSecret }
    $body = @{ mode = $Mode } | ConvertTo-Json -Compress
    $triggerUri = $ApiBaseUrl.TrimEnd('/') + '/api/v1/worker/trigger'
    $first = Invoke-RestMethod `
        -Method Post `
        -Uri $triggerUri `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $body `
        -TimeoutSec 250
    $second = Invoke-RestMethod `
        -Method Post `
        -Uri $triggerUri `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $body `
        -TimeoutSec 250

    if ($Mode -eq 'process_import') {
        $evidence = [pscustomobject]@{
            status = $first.status
            mode = $first.mode
            worker_authenticated = [bool]$first.worker_authenticated
            state = $first.progress.state
            processed_file_count = [int]$first.progress.processed_file_count
            total_file_count = [int]$first.progress.total_file_count
            normalized_record_count = [long]$first.progress.normalized_record_count
            warning_codes = @($first.progress.warning_codes)
            replay_state = $second.progress.state
        }
        if (
            $evidence.status -ne 'ok' -or
            -not $evidence.worker_authenticated -or
            $evidence.state -ne 'completed_with_warnings' -or
            $evidence.processed_file_count -ne 1 -or
            $evidence.total_file_count -ne 1 -or
            $evidence.normalized_record_count -ne 6 -or
            $evidence.warning_codes -notcontains 'sensitive_record_excluded' -or
            $evidence.replay_state -ne 'idle'
        ) {
            throw ('staging_process_import_acceptance_failed:' + ($evidence | ConvertTo-Json -Compress))
        }
    } else {
        $evidence = [pscustomobject]@{
            status = $first.status
            mode = $first.mode
            worker_authenticated = [bool]$first.worker_authenticated
            state = $first.cleanup.state
            processed_import_count = [int]$first.cleanup.processed_import_count
            deleted_object_count = [int]$first.cleanup.deleted_object_count
            replay_state = $second.cleanup.state
            replay_processed_import_count = [int]$second.cleanup.processed_import_count
        }
        if (
            $evidence.status -ne 'ok' -or
            -not $evidence.worker_authenticated -or
            $evidence.state -ne 'completed' -or
            $evidence.processed_import_count -ne 1 -or
            $evidence.deleted_object_count -ne 1 -or
            $evidence.replay_state -ne 'idle' -or
            $evidence.replay_processed_import_count -ne 0
        ) {
            throw ('staging_cleanup_acceptance_failed:' + ($evidence | ConvertTo-Json -Compress))
        }
    }
} finally {
    try {
        Set-ProcessImportGate $false
        Deploy-StagingApi
    } catch {
        $restoreError = $_
    }
    $triggerSecret = $null
    [Array]::Clear($secretBytes, 0, $secretBytes.Length)
}

if ($null -ne $restoreError) {
    throw 'staging_worker_gate_restore_failed'
}

$evidence | ConvertTo-Json
