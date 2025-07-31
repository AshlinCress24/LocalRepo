param (
    [string] $package_path = "$env:GITHUB_WORKSPACE\package",
    [string] $orchestrator_url = $env:ORCH_URL,
    [string] $organization_name = $env:ORCH_ORGANIZATION_NAME,
    [string] $orchestrator_tenant = $env:ORCH_TENANT,
    [string] $client_id = $env:ORCH_CLIENT_ID,
    [string] $client_secret = $env:ORCH_CLIENT_SECRET,
    [string] $folder_organization_unit = $env:ORCH_DEV_FOLDER_PATH
)

function WriteLog {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "$timestamp - $message"
}

WriteLog "🔎 Parameters received:"
WriteLog "🔎 package_path: $package_path"
WriteLog "🔎 orchestrator_url: $orchestrator_url"
WriteLog "🔎 organization_name: $organization_name"
WriteLog "🔎 orchestrator_tenant: $orchestrator_tenant"
WriteLog "🔎 client_id: $client_id"
WriteLog "🔎 client_secret: [hidden]"
WriteLog "🔎 folder_organization_unit: $folder_organization_unit"

# Validate all inputs
if (-not $package_path -or -not $orchestrator_url -or -not $organization_name -or -not $orchestrator_tenant -or -not $client_id -or -not $client_secret -or -not $folder_organization_unit) {
    WriteLog "❌ ❌ Required parameters missing. Please ensure all are provided."
    exit 1
}

# Get the .nupkg file
$nupkg = Get-ChildItem -Path $package_path -Filter *.nupkg | Select-Object -First 1
if (-not $nupkg) {
    WriteLog "❌ No .nupkg file found in package path: $package_path"
    exit 1
}
WriteLog "📦 Found package: $($nupkg.FullName)"

# Get Auth Token - External App Auth Flow
$authBody = @{
    grant_type    = "client_credentials"
    client_id     = $client_id
    client_secret = $client_secret
    scope         = "OR.Platform"
}

$tokenUrl = "https://cloud.uipath.com/identity_/connect/token"
WriteLog "🔐 Getting token from: $tokenUrl"

try {
    $authResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $authBody -ContentType "application/x-www-form-urlencoded"
} catch {
    WriteLog "❌ Failed to get token: $($_.Exception.Message)"
    exit 1
}

$accessToken = $authResponse.access_token
if (-not $accessToken) {
    WriteLog "❌ Failed to retrieve access token"
    exit 1
}
WriteLog "✅ Access token retrieved"

# Upload Package
$deployUri = "$orchestrator_url$organization_name/$orchestrator_tenant/odata/Processes/UiPath.Server.Configuration.OData.UploadPackage"
WriteLog "🚀 Uploading package to: $deployUri"

try {
    $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
    $fileContent = [System.IO.File]::ReadAllBytes($nupkg.FullName)
    $byteArrayContent = [System.Net.Http.ByteArrayContent]::new($fileContent)
    $byteArrayContent.Headers.Add("Content-Type", "application/octet-stream")
    $multipartContent.Add($byteArrayContent, "file", $nupkg.Name)

    $handler = New-Object System.Net.Http.HttpClientHandler
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.DefaultRequestHeaders.Authorization = "Bearer $accessToken"

    $response = $client.PostAsync($deployUri, $multipartContent).Result

    if ($response.IsSuccessStatusCode) {
        WriteLog "✅ Package uploaded successfully."
    } else {
        $respContent = $response.Content.ReadAsStringAsync().Result
        WriteLog "❌ Upload failed: $($response.StatusCode) - $respContent"
        exit 1
    }
} catch {
    WriteLog "❌ Exception during upload: $($_.Exception.Message)"
    exit 1
}
