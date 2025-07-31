<#
.SYNOPSIS
    Deploy NuGet package files to orchestrator

.DESCRIPTION
    This script deploys NuGet package files (*.nupkg) to Cloud or On-Prem orchestrator using Client ID and Client Secret authentication.

.PARAMETER packages_path
    Required. The path to a folder containing packages, or to a package file.

.PARAMETER orchestrator_url
    Required. The base URL of the Orchestrator instance (e.g., https://cloud.uipath.com).

.PARAMETER organization_name
    Required. The UiPath Cloud organization name (e.g., noviggptduln).

.PARAMETER orchestrator_tenant
    Required. The tenant of the Orchestrator instance (e.g., DefaultTenant).

.PARAMETER client_id
    Required. The Client ID from your Orchestrator External Application.

.PARAMETER client_secret
    Required. The Client Secret from your Orchestrator External Application.

.PARAMETER folder_organization_unit
    The Orchestrator folder (modern folder path/name).

.PARAMETER environment_list
    For classic folders: comma-separated list of environments.

.PARAMETER language
    The orchestrator language.

.PARAMETER disableTelemetry
    Disable telemetry data.
#>

Param (
    [string] $packages_path = $env:UIPATH_PACKAGE_PATH,
    [string] $orchestrator_url = $env:UIPATH_ORCH_URL,
    [string] $organization_name = $env:UIPATH_ORCH_ORG_NAME,
    [string] $orchestrator_tenant = $env:UIPATH_ORCH_TENANT_NAME,
    [string] $client_id = $env:UIPATH_CLIENT_ID,
    [string] $client_secret = $env:UIPATH_CLIENT_SECRET,
    [string] $folder_organization_unit = $env:UIPATH_FOLDER_NAME,
    [string] $language = "",
    [string] $environment_list = "",
    [string] $disableTelemetry = ""
)

function WriteLog {
    Param ($message, [switch] $err)
    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($err) {
        Write-Host "$now - ❌ $message" -ForegroundColor Red
    } else {
        Write-Host "$now - 🔎 $message"
    }
}

WriteLog "Parameters received:"
WriteLog "package_path: $packages_path"
WriteLog "orchestrator_url: $orchestrator_url"
WriteLog "organization_name: $organization_name"
WriteLog "orchestrator_tenant: $orchestrator_tenant"
WriteLog "client_id: $client_id"
WriteLog "client_secret: [hidden]"
WriteLog "folder_organization_unit: $folder_organization_unit"

if (
    [string]::IsNullOrWhiteSpace($packages_path) -or
    [string]::IsNullOrWhiteSpace($orchestrator_url) -or
    [string]::IsNullOrWhiteSpace($organization_name) -or
    [string]::IsNullOrWhiteSpace($orchestrator_tenant) -or
    [string]::IsNullOrWhiteSpace($client_id) -or
    [string]::IsNullOrWhiteSpace($client_secret)
) {
    WriteLog "❌ Required parameters missing. Please ensure all are provided." -err
    Exit 1
}

$uipathCLI = "uipath"
WriteLog "Using CLI: $uipathCLI"

# Authenticate
WriteLog "Configuring UiPath CLI authentication..."
$authCmd = @(
    "config", "--auth", "credentials",
    "--organization", $organization_name,
    "--tenant", $orchestrator_tenant,
    "--clientId", $client_id,
    "--clientSecret", $client_secret
)
if ($orchestrator_url -ne "https://cloud.uipath.com") {
    $authCmd += @("--uri", $orchestrator_url)
}

& $uipathCLI $authCmd
if ($LASTEXITCODE -ne 0) {
    WriteLog "❌ Failed to authenticate with UiPath CLI." -err
    Exit 1
}

WriteLog "✅ UiPath CLI authentication configured."

# Upload package
WriteLog "Preparing to upload package..."
$deployCmd = @("orchestrator", "packages", "upload")

# Determine .nupkg file
if (Test-Path $packages_path -PathType Container) {
    $nupkgFile = Get-ChildItem -Path $packages_path -Filter "*.nupkg" -Recurse | Select-Object -First 1
    if (-not $nupkgFile) {
        WriteLog "❌ No .nupkg files found in directory." -err
        Exit 1
    }
    $deployCmd += @("-file", $nupkgFile.FullName)
    WriteLog "Found package: $($nupkgFile.FullName)"
} elseif (Test-Path $packages_path -PathType Leaf -and $packages_path.EndsWith(".nupkg")) {
    $deployCmd += @("-file", $packages_path)
    WriteLog "Using specified package: $packages_path"
} else {
    WriteLog "❌ Invalid packages_path: not a folder or .nupkg file." -err
    Exit 1
}

if ($folder_organization_unit -ne "") {
    $deployCmd += @("--folder-path", $folder_organization_unit)
}

if ($environment_list -ne "") {
    WriteLog "⚠️ Using environment_list (for classic folders)."
    $deployCmd += @("--environment", $environment_list)
}

if ($disableTelemetry -ne "") {
    $deployCmd += @("--telemetry-opt-out")
}

WriteLog "Executing package upload..."
& $uipathCLI $deployCmd

if ($LASTEXITCODE -eq 0) {
    WriteLog "✅ Package uploaded successfully."
    Exit 0
} else {
    WriteLog "❌ Failed to upload package. Exit code: $LASTEXITCODE" -err
    Exit 1
}
