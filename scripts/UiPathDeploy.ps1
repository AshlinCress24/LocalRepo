Param(
    [string] $package_path = "",
    [string] $orchestrator_url = "",
    [string] $orchestrator_tenant = "",
    [string] $client_id = "",
    [string] $client_secret = ""
)

function WriteLog {
    param($msg)
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg"
}

# Validate inputs
if ($package_path -eq "" -or $orchestrator_url -eq "" -or $orchestrator_tenant -eq "" -or $client_id -eq "" -or $client_secret -eq "") {
    WriteLog "❌ Required parameters missing. Please ensure all are provided."
    exit 1
}

# Find the .nupkg file
$nupkg = Get-ChildItem -Path $package_path -Filter *.nupkg | Select-Object -First 1
if (-not $nupkg) {
    WriteLog "❌ No .nupkg file found in path: $package_path"
    exit 1
}

WriteLog "📦 Package found: $($nupkg.FullName)"

# Extract account name from orchestrator_url for scope generation
if ($orchestrator_url -match "https:\/\/cloud.uipath.com\/([^\/]+)") {
    $account_name = $matches[1]
    $scope = "OR.$account_name.$orchestrator_tenant"
    WriteLog "🔍 Account name extracted: $account_name"
    WriteLog "🔍 Scope generated: $scope"
} else {
    WriteLog "❌ Could not extract account name from Orchestrator URL"
    exit 1
}

# Get OAuth2 access token using External App credentials
$tokenUrl = "$orchestrator_url/identity_/connect/token"
$tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $client_id
    client_secret = $client_secret
    scope         = $scope
}

WriteLog "🔐 Requesting access token..."

try {
    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
    $accessToken = $tokenResponse.access_token
    if (-not $accessToken) {
        WriteLog "❌ Access token not retrieved"
        exit 1
    }
    WriteLog "✅ Access token acquired"
} catch {
    WriteLog "❌ Failed to acquire access token: $_"
    exit 1
}

# Upload the package using Orchestrator API
$deployUri = "$orchestrator_url/odata/Processes/UiPath.Server.Configuration.OData.UploadPackage"
WriteLog "☁️ Uploading package to: $deployUri"

try {
    $headers = @{
        "Authorization" = "Bearer $accessToken"
    }
    $form = @{
        file = Get-Item $nupkg.FullName
    }

    $response = Invoke-RestMethod -Uri $deployUri -Method Post -Headers $headers -Form $form
    WriteLog "✅ Package uploaded successfully"
} catch {
    WriteLog "❌ Upload failed: $_"
    exit 1
}
