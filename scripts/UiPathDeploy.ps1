<#
.SYNOPSIS
    Deploy NuGet package files to orchestrator

.DESCRIPTION
    This script is to deploy NuGet package files (*.nupkg) to Cloud or On-Prem orchestrator using Client ID and Client Secret authentication.

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
    The Orchestrator folder (organization unit). This is typically the modern folder path/name.

.PARAMETER environment_list
    For classic folders, the comma-separated list of environments to deploy the package to. If the environment does not belong to the default folder (organization unit) it must be prefixed with the folder name, e.g. AccountingTeam\TestEnvironment. (Less common with modern folders)

.PARAMETER language
    The orchestrator language.

.PARAMETER disableTelemetry
    Disable telemetry data.

.EXAMPLE
SYNTAX
    . '\UiPathDeploy.ps1' <packages_path> <orchestrator_url> <organization_name> <orchestrator_tenant> -client_id <client_id> -client_secret <client_secret> [-folder_organization_unit <folder_organization_unit>] [-environment_list <environment_list>] [-language <language>]
Examples:
    . '\UiPathDeploy.ps1' "C:\UiPath\Project\Package.1.0.nupkg" "https://cloud.uipath.com" "myorg" "DefaultTenant" -client_id "your_client_id" -client_secret "your_client_secret"
    . '\UiPathDeploy.ps1' "C:\UiPath\Project\Package.1.0.nupkg" "https://cloud.uipath.com" "myorg" "DefaultTenant" -client_id "your_client_id" -client_secret "your_client_secret" -folder_organization_unit "MyProjectFolder"
#>
Param (
    #Required
    [string] $packages_path = "", # Required. The path to a folder containing packages, or to a package file.
    [string] $orchestrator_url = "", # Required. The base URL of the Orchestrator instance (e.g., https://cloud.uipath.com).
    [string] $organization_name = "", # Required. The UiPath Cloud organization name.
    [string] $orchestrator_tenant = "", # Required. The tenant of the Orchestrator instance.
    [string] $client_id = "", # Required. The Client ID from External Application.
    [string] $client_secret = "", # Required. The Client Secret from External Application.

    [string] $folder_organization_unit = "", # The Orchestrator folder (organization unit).
    [string] $language = "", # The orchestrator language.
    [string] $environment_list = "", # The comma-separated list of environments (for classic folders).
    [string] $disableTelemetry = "" # Disable telemetry data.
)

function WriteLog
{
    Param ($message, [switch] $err)

    $now = Get-Date -Format "G"
    $line = "$now`t$message"
    $line | Add-Content $debugLog -Encoding UTF8
    if ($err)
    {
        Write-Host $line -ForegroundColor red
    } else {
        Write-Host $line
    }
}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog = "$scriptPath\orchestrator-package-deploy.log"

# --- REMOVING MANUAL CLI DOWNLOAD ---
# The UiPath/setup-uipath-cli@v1 GitHub Action will handle this.
# Assuming 'uipath' command is available in PATH due to the GitHub Action.
$uipathCLI = "uipath" # Changed to just 'uipath' as it should be in PATH
WriteLog "-----------------------------------------------------------------------------"
WriteLog "uipath CLI will be invoked from PATH."

# --- Parameter Validation ---
if (
    $packages_path -eq "" -or
    $orchestrator_url -eq "" -or
    $organization_name -eq "" -or
    $orchestrator_tenant -eq "" -or
    $client_id -eq "" -or
    $client_secret -eq ""
) {
    WriteLog "Error: Missing required parameters for Client ID/Secret authentication." -err
    WriteLog "Required parameters: packages_path, orchestrator_url, organization_name, orchestrator_tenant, client_id, client_secret." -err
    exit 1
}

# --- Authenticate UiPath CLI using Client ID and Client Secret ---
WriteLog "Configuring UiPath CLI authentication..."
$authParams = New-Object 'Collections.Generic.List[string]'
$authParams.Add("config")
$authParams.Add("--auth")
$authParams.Add("credentials")
$authParams.Add("--organization")
$authParams.Add($organization_name)
$authParams.Add("--tenant")
$authParams.Add($orchestrator_tenant)
$authParams.Add("--clientId")
$authParams.Add($client_id)
$authParams.Add("--clientSecret")
$authParams.Add($client_secret)
if ($orchestrator_url -ne "https://cloud.uipath.com") {
    # Only add --uri if it's not the default cloud URL
    $authParams.Add("--uri")
    $authParams.Add($orchestrator_url)
}

# Mask client secret for logging
$authParamsMasked = New-Object 'Collections.Generic.List[string]'
$authParamsMasked.AddRange($authParams)
$secretIndex = $authParamsMasked.IndexOf("--clientSecret")
if ($secretIndex -ge 0) {
    $authParamsMasked[$secretIndex + 1] = ("*" * 8) # Mask secret
}
WriteLog "Executing $uipathCLI $($authParamsMasked -join ' ')"

& "$uipathCLI" $authParams.ToArray()
if ($LASTEXITCODE -ne 0) {
    WriteLog "Failed to configure UiPath CLI authentication. Exit code: $LASTEXITCODE" -err
    exit 1
}
WriteLog "UiPath CLI authentication configured successfully."

# --- Building uipath cli parameters for package deployment ---
$deployParams = New-Object 'Collections.Generic.List[string]'
$deployParams.Add("orchestrator") # Use 'orchestrator' verb for modern CLI
$deployParams.Add("packages")
$deployParams.Add("upload") # Or 'deploy' for older versions, 'upload' is for nupkg files

# Check if packages_path is a directory or a specific .nupkg file
if (Test-Path -Path $packages_path -PathType Container) {
    # It's a directory, find all .nupkg files
    $packageFiles = Get-ChildItem -Path $packages_path -Filter "*.nupkg" -Recurse | Select-Object -ExpandProperty FullName
    if (-not $packageFiles) {
        WriteLog "No .nupkg files found in directory: $packages_path" -err
        exit 1
    }
    # For simplicity, let's assume we deploy the first one found or iterate
    # For typical CI/CD, the build step produces one NUPKG
    $nupkgToUpload = $packageFiles | Select-Object -First 1
    WriteLog "Found package to upload: $nupkgToUpload"
    $deployParams.Add("-file")
    $deployParams.Add($nupkgToUpload)
} elseif (Test-Path -Path $packages_path -PathType Leaf -and $packages_path.EndsWith(".nupkg")) {
    # It's a specific .nupkg file
    WriteLog "Uploading specific package file: $packages_path"
    $deployParams.Add("-file")
    $deployParams.Add($packages_path)
} else {
    WriteLog "Error: packages_path must be a directory containing .nupkg files or a specific .nupkg file." -err
    exit 1
}

# Add folder/environment if specified
if ($folder_organization_unit -ne "") {
    $deployParams.Add("--folder-path") # Use --folder-path for modern folders
    $deployParams.Add($folder_organization_unit)
} elseif ($environment_list -ne "") {
    # For classic environments, if folder_organization_unit is not used
    WriteLog "Warning: --environment parameter is primarily for classic folders. Consider --folder-path for modern folders."
    $deployParams.Add("--environment")
    $deployParams.Add($environment_list)
}

if ($language -ne "") {
    WriteLog "Warning: 'language' parameter might not be directly supported for package upload. Check UiPath CLI documentation."
    # The CLI doesn't typically have a -l for package upload. This might be for other CLI commands.
    # $deployParams.Add("-l")
    # $deployParams.Add($language)
}

if ($disableTelemetry -ne "") {
    # Most CLI commands accept --telemetry-opt-out
    $deployParams.Add("--telemetry-opt-out")
}

# Log cli call with parameters (masking sensitive info)
$deployParamsMasked = New-Object 'Collections.Generic.List[string]'
$deployParamsMasked.AddRange($deployParams)
# No sensitive info in deploy command parameters if auth is handled by config command

WriteLog "Executing $uipathCLI $($deployParamsMasked -join ' ')"

# Call uipath cli for package upload
& "$uipathCLI" $deployParams.ToArray()

if ($LASTEXITCODE -eq 0) {
    WriteLog "Package deployed successfully!"
    Exit 0
} else {
    WriteLog "Unable to deploy project. Exit code $LASTEXITCODE" -err
    Exit 1
}
