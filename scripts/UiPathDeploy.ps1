param (
    [string] $package_path = "$PSScriptRoot\..\package",
    [string] $orchestrator_url = $env:ORCH_URL,
    [string] $organization_name = $env:ORCH_ORGANIZATION_NAME,
    [string] $orchestrator_tenant = $env:ORCH_TENANT,
    [string] $client_id = $env:ORCH_CLIENT_ID,
    [string] $client_secret = $env:ORCH_CLIENT_SECRET,
    [string] $folder_organization_unit = $env:ORCH_DEV_FOLDER_PATH
)

function WriteLog {
    param([string]$message)
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message"
}

WriteLog "🔎 Parameters received:"
WriteLog "🔎 package_path: $package_path"
WriteLog "🔎 orchestrator_url: $orchestrator_url"
WriteLog "🔎 organization_name: $organization_name"
WriteLog "🔎 orchestrator_tenant: $orchestrator_tenant"
WriteLog "🔎 client_id: $client_id"
WriteLog "🔎 client_secret: [hidden]"
WriteLog "🔎 folder_organization_unit: $folder_organization_unit"

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($package_path) -or
    [string]::IsNullOrWhiteSpace($orchestrator_url) -or
    [string]::IsNullOrWhiteSpace($organization_name) -or
    [string]::IsNullOrWhiteSpace($orchestrator_tenant) -or
    [string]::IsNullOrWhiteSpace($client_id) -or
    [string]::IsNullOrWhiteSpace($client_secret) -or
    [string]::IsNullOrWhiteSpace($folder_organization_unit)) {
    
    WriteLog "❌ ❌ Required parameters missing. Please ensure all are provided."
    exit 1
}

# Find the .nupkg file
$package = Get-ChildItem -Path $package_path -Filter *.nupkg | Select-Object -First 1
if (-not $package) {
    WriteLog "❌ No .nupkg package found in $package_path"
    exit 1
}
WriteLog "📦 Found package: $($package.FullName)"

# Construct token URL
$tokenUrl = "$orchestrator_url/identity_/connect/token"
WriteLog "🔐 Getting token from: $tokenUrl"

# Request token using External App flow
$authBody = @{
    grant_type    = "client_credentials"
    client_id     = $client_id
    client_secret = $client_secret
    scope         = "OR.Folders.Read OR.Execution.Write OR.Jobs.Write OR.Jobs.Read"
}

try {
    $response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $authBody -ContentType "application/x-www-form-urlencoded"
    $access_token = $response.access_token
    WriteLog "✅ Token acquired successfully"
} catch {
    WriteLog "❌ Failed to get token: $_"
    exit 1
}

# Upload the package to Orchestrator
$deployUri = "$orchestrator_url/$organization_name/$orchestrator_tenant/odata/Processes/UiPath.Server.Configuration.OData.UploadPackage"
WriteLog "⬆️ Uploading package to: $deployUri"

try {
    $form = @{
        file = Get-Item $package.FullName
    }

    $uploadResponse = Invoke-RestMethod -Method Post -Uri $deployUri `
        -Headers @{ Authorization = "Bearer $access_token" } `
        -Form $form

    WriteLog "✅ Package deployed successfully"
} catch {
    WriteLog "❌ Failed to deploy package: $_"
    exit 1
}
