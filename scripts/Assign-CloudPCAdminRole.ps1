<#
.SYNOPSIS
    Assigns the Windows 365 Administrator role to the Project Fidalgo service principal.

.DESCRIPTION
    This script connects to Microsoft Graph and assigns the Windows 365 Administrator role
    to the Project Fidalgo service principal (AppId: 2dc3760b-4713-48b1-a383-1dfe3e449ec2).
    If the service principal is not found, the script will attempt to register the Microsoft.DevCenter
    resource provider in the selected Azure subscription and retry the lookup. The script includes
    error handling, verification steps, and prompts for tenant/account selection as needed.

.PARAMETER SkipLoadingModules
    Skips checking for and loading Microsoft Graph modules. Use this parameter if you have already
    ensured the required modules are installed and imported.

.PARAMETER WhatIf
    Runs the script in WhatIf mode, simulating actions without making any changes.

.NOTES
    - Requires PowerShell 7 (pwsh) or higher.
    - Requires Azure CLI (az) to be installed and available in PATH (optional - only if resource provider registration is needed).
    - Requires appropriate Microsoft Entra ID (Azure AD) and Azure permissions (see README for details).
    - The script will prompt for Azure CLI login and subscription selection if resource provider registration is needed.

.LINK

.EXAMPLE
# Checkin Dev manifest
.\Assign-CloudPCAdminRole.ps1

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch] $WhatIf = $false,

    [Parameter(Mandatory = $false)]
    [switch] $SkipLoadingModules = $false
)

# Function to register Microsoft.DevCenter resource provider in the correct tenant and subscription
function Register-DevCenterResourceProvider {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )
    $azCli = Get-Command az -ErrorAction SilentlyContinue
    if ($null -eq $azCli) {
        Handle-Error -ErrorMessage "Azure CLI (az) is not installed or not available in PATH. Please install Azure CLI from https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?view=azure-cli-latest&pivots=msi and try again." -Exit $true
    }
    $azTenant = az account show --query tenantId -o tsv 2>$null
    if ($azTenant -ne $TenantId) {
        Write-Host ("Logging in to Azure CLI (TenantId: {0})..." -f $TenantId) -ForegroundColor Yellow
        az login --tenant $TenantId | Out-Null
    }
    Write-Host "Retrieving Azure subscriptions for tenant $($TenantId):" -ForegroundColor Cyan
    $subscriptionsJson = az account list --query "[?state=='Enabled' && tenantId=='$TenantId']" -o json
    $subscriptions = $null
    try {
        $subscriptions = $subscriptionsJson | ConvertFrom-Json
    }
    catch {
        Handle-Error -ErrorMessage "Failed to parse Azure subscriptions. Error: $_" -Exit $true
    }
    if ($null -eq $subscriptions -or $subscriptions.Count -eq 0) {
        Handle-Error -ErrorMessage "No enabled Azure subscriptions found for tenant $TenantId." -Exit $true
    }
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        $sub = $subscriptions[$i]
        Write-Host ("[{0}] {1} ({2})" -f $i, $sub.name, $sub.id)
    }
    $selectedIndex = Read-Host "Enter the number of the subscription to use for resource provider registration (default 0)"
    if ([string]::IsNullOrWhiteSpace($selectedIndex)) { $selectedIndex = 0 }
    if ($selectedIndex -notmatch '^[0-9]+$' -or $selectedIndex -ge $subscriptions.Count) {
        Handle-Error -ErrorMessage "Invalid subscription selection." -Exit $true
    }
    $selectedSub = $subscriptions[$selectedIndex]
    $selectedSubId = $selectedSub.id
    Write-Host "Setting active subscription to: $($selectedSub.name) ($selectedSubId) in tenant $TenantId" -ForegroundColor Yellow
    az account set --subscription $selectedSubId
    $registerResult = az provider register --namespace Microsoft.DevCenter 2>&1
    if ($LASTEXITCODE -ne 0) {
        Handle-Error -ErrorMessage "Failed to register Microsoft.DevCenter resource provider. Azure CLI returned exit code $LASTEXITCODE. Output: $registerResult" -Exit $true
    }
    $maxAttempts = 15
    $attempt = 0
    do {
        Start-Sleep -Seconds 5
        $status = az provider show --namespace Microsoft.DevCenter --query "registrationState" -o tsv 2>$null
        $attempt++
        Write-Host "Waiting for Microsoft.DevCenter registration... (Attempt $attempt, Status: $status)"
    } while ($status -ne "Registered" -and $attempt -lt $maxAttempts)
    if ($status -ne "Registered") {
        Handle-Error -ErrorMessage "Microsoft.DevCenter resource provider registration did not complete in time. Please check your Azure subscription and try again." -Exit $true
    }
    Write-Host "Microsoft.DevCenter resource provider registered. Retrying service principal lookup..." -ForegroundColor Yellow
}

# Function for error handling
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [bool]$Exit = $false
    )
    
    Write-Error $ErrorMessage
    if ($Exit) {
        exit 1
    }
}

# Function to get and display tenant information
function Get-TenantDisplayInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )
    
    try {
        $org = Get-MgOrganization -ErrorAction SilentlyContinue
        if ($null -ne $org) {
            $tenantName = $org.DisplayName
            Write-Host "`nConnected to tenant: $tenantName ($TenantId)" -ForegroundColor Cyan
            return $tenantName
        }
        else {
            Write-Host "`nConnected to tenant ID: $TenantId" -ForegroundColor Cyan
            return $null
        }
    }
    catch {
        Write-Host "`nConnected to tenant ID: $TenantId" -ForegroundColor Cyan
        return $null
    }
}

# Function to show a progress indicator while a script block runs
function Show-Progress {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [string]$Activity = "Processing...",
        [int]$Delay = 100
    )
    $progress = $true
    $job = Start-Job -ScriptBlock $ScriptBlock
    $i = 0
    $spinner = @('|', '/', '-', '\')
    while ($progress) {
        $state = Get-Job -Id $job.Id | Where-Object { $_.State -eq 'Running' }
        if ($null -eq $state) { $progress = $false; break }
        Write-Host -NoNewline ("`r{0} {1}" -f $spinner[$i % $spinner.Length], $Activity)
        Start-Sleep -Milliseconds $Delay
        $i++
    }
    Write-Host "`r$Activity... Done.           "
    Receive-Job -Id $job.Id | Out-Null
    Remove-Job -Id $job.Id | Out-Null
}


# Require PowerShell 7+
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7 or higher. Please install PowerShell 7 from https://aka.ms/powershell and run this script using 'pwsh'."
    exit 1
}

# Set constants for service principal and role
$AppId = "2dc3760b-4713-48b1-a383-1dfe3e449ec2" # DevCenter (Project Fidalgo) service principal AppId

# Check for Microsoft Graph module
if (-not $SkipLoadingModules) {
    try {
        Write-Host "Checking for Microsoft Graph modules..." -ForegroundColor Yellow
        $mgModule = Get-Module -ListAvailable -Name Microsoft.Graph
        
        # Set PSGallery as trusted if needed
        if ((Get-PSRepository -Name "PSGallery").InstallationPolicy -ne "Trusted") {
            Write-Host "Setting PSGallery as trusted repository..."
            Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
        }
        
        if ($null -eq $mgModule) {
            Write-Host "Microsoft Graph module not found. Installing required modules..." -ForegroundColor Yellow
            
            # Install modules with more permissive options
            Show-Progress -Activity "Installing Microsoft.Graph module" -ScriptBlock {
                Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
            }
            Write-Host "Microsoft.Graph module installed." -ForegroundColor Green
            
            # Is this one still necessary?
            #Show-Progress -Activity "Installing Microsoft.Graph.Identity.Governance module" -ScriptBlock {
            #    Install-Module Microsoft.Graph.Identity.Governance -Scope CurrentUser -Force -AllowClobber
            #}
            #Write-Host "Microsoft.Graph.Identity.Governance module installed." -ForegroundColor Green

            Show-Progress -Activity "Microsoft.Graph.Authentication module" -ScriptBlock {
                Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
            }
            Write-Host "Microsoft.Graph.Authentication module installed." -ForegroundColor Green
        }
        else {
            Write-Host "Microsoft Graph module is already installed." -ForegroundColor Green
        }
    }
    catch {
        Handle-Error -ErrorMessage "Failed to check or install Microsoft Graph module: $_" -Exit $true
    }

    # Import required modules
    try {
        Write-Host "Importing Microsoft Graph modules..." -ForegroundColor Yellow
        Write-Host "This process may take a minute or two, especially on first run." -ForegroundColor Yellow

        Show-Progress -Activity "Loading Microsoft Graph modules" -ScriptBlock {
            if (-not (Get-Module -Name Microsoft.Graph)) {
                Import-Module Microsoft.Graph -MinimumVersion 1.0.0 -Force -ErrorAction Stop
            }
            #if (-not (Get-Module -Name Microsoft.Graph.Identity.Governance)) {
            #    Import-Module Microsoft.Graph.Identity.Governance -MinimumVersion 1.0.0 -Force -ErrorAction Stop
            #}

            if (-not (Get-Module -Name Microsoft.Graph.Authentication)) {
                Import-Module Microsoft.Graph.Authentication -MinimumVersion 1.0.0 -Force -ErrorAction Stop
            }
        }
        Write-Host "Microsoft Graph modules successfully imported." -ForegroundColor Green
    }
    catch {
        Write-Host "`r" -NoNewline
        Handle-Error -ErrorMessage "Failed to import Microsoft Graph modules: $_" -Exit $true
    }
}

# Connect to Microsoft Graph with appropriate permissions
try {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    
    # First connect to Graph with basic permissions
    #Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory", "Application.Read.All" -NoWelcome -ErrorAction Stop
    Connect-MgGraph -Scopes "Directory.Read.All, AppRoleAssignment.ReadWrite.All, Application.Read.All" -ErrorAction Stop
    
    # Now that we're connected, get the tenant info
    $context = Get-MgContext
    if ($null -ne $context) {
        $tenantId = $context.TenantId

        # Get and display tenant information
        Get-TenantDisplayInfo -TenantId $tenantId
        
        # Ask if user wants to use this tenant or switch, including account info
        $accountName = $context.Account
        $useDefault = Read-Host "`nDo you want to continue as '$accountName' in this tenant? (Y/N) [Y]"
        
        if (!($useDefault -eq "" -or $useDefault.ToLower() -eq "y")) {
            # User wants to switch tenants
            Write-Host "Disconnecting from current tenant..." -ForegroundColor Yellow
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            
            Write-Host "Please select your desired tenant in the login window..." -ForegroundColor Yellow
            Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory", "Application.Read.All" -ErrorAction Stop
            
            # Show the new tenant info
            $newContext = Get-MgContext
            if ($null -ne $newContext) {
                $newTenantId = $newContext.TenantId
                $newAccountName = $newContext.Account
                Write-Host "Successfully connected to tenant as '$newAccountName'." -ForegroundColor Green
                
                # Get and display new tenant information
                Get-TenantDisplayInfo -TenantId $newTenantId
            }
        }
        else {
            Write-Host "Continuing with current tenant." -ForegroundColor Green
        }
    } 
    else {
        throw "Could not establish a Microsoft Graph connection."
    }
}
catch {
    Handle-Error -ErrorMessage "Failed to connect to Microsoft Graph: $_" -Exit $true
}

# Get the service principal
try {
    Write-Host "Getting service principal with AppId '$AppId'..." -ForegroundColor Yellow
    $servicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$AppId'" -ErrorAction SilentlyContinue
    if ($null -eq $servicePrincipal) {
        Write-Warning "Service principal with AppId '$AppId' not found. Attempting to register Microsoft.DevCenter resource provider... You may be prompted to log in to Azure again."
        if ($WhatIf) {
            Write-Host "WhatIf: Skipping registration of Microsoft.DevCenter resource provider." -ForegroundColor Yellow
            break
        }

        Register-DevCenterResourceProvider -TenantId $tenantId
        $servicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$AppId'" -ErrorAction SilentlyContinue
        if ($null -eq $servicePrincipal) {
            Handle-Error -ErrorMessage "Service principal with AppId '$AppId' still not found after registering Microsoft.DevCenter." -Exit $true
        }
    }
    $servicePrincipalId = $servicePrincipal.Id
    Write-Host "Service Principal ID: $servicePrincipalId" -ForegroundColor Green
}
catch {
    Handle-Error -ErrorMessage "Failed to get service principal: $_" -Exit $true
}

# Get the Microsoft Graph service principal
try {
    Write-Host "Getting Microsoft Graph service principal..." -ForegroundColor Yellow
    $GraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
    if ($null -eq $GraphServicePrincipal) {
        Handle-Error -ErrorMessage "Microsoft Graph service principal not found." -Exit $true
    }
}
catch {
    Handle-Error -ErrorMessage "Failed to get Microsoft Graph service principal: $_" -Exit $true
}

# Find the app role for CloudPC.ReadWrite.All
$AppRole = $GraphServicePrincipal.AppRoles | Where-Object { $_.Value -eq 'CloudPC.ReadWrite.All' -and $_.AllowedMemberTypes -contains 'Application' }

# Check if the role is already assigned
try {
    Write-Host "Checking if role is already assigned..." -ForegroundColor Yellow
    $existingAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipalId | Where-Object { $_.AppRoleId -eq $AppRole.Id -and $_.ResourceId -contains $GraphServicePrincipal.Id }
    $RoleName = $AppRole.Value
    if ($null -ne $existingAssignment) {
        Write-Host "Role '$RoleName' is already assigned to the service principal $servicePrincipalId." -ForegroundColor Green
        $roleAssignmentId = $existingAssignment.Id
        Write-Host "Role Assignment ID: $roleAssignmentId" -ForegroundColor Green
        
        exit 0
    }
}
catch {
    Write-Warning "Error checking existing role assignment: $_"
    # Continue anyway as we'll try to create a new assignment
}

# Assign the role to the service principal
try {
    Write-Host "Assigning '$RoleName' role to the service principal..." -ForegroundColor Yellow

    if ($WhatIf) {
        Write-Host "WhatIf: Skipping assignment of '$RoleName' role to the service principal." -ForegroundColor Yellow
        Write-Host "New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipalId -PrincipalId $servicePrincipalId -ResourceId " + $GraphServicePrincipal.Id + " -AppRoleId " + $AppRole.Id
        break
    }

    $newAssignment = New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipalId -PrincipalId $servicePrincipalId -ResourceId $GraphServicePrincipal.Id -AppRoleId $AppRole.Id
    
    if ($null -eq $newAssignment) {
        Handle-Error -ErrorMessage "Failed to create role assignment." -Exit $true
    }
    
    Write-Host "Successfully assigned '$RoleName' role to the service principal." -ForegroundColor Green
    Write-Host "Role Assignment ID: $($newAssignment.Id)" -ForegroundColor Green
}
catch {
    Handle-Error -ErrorMessage "Failed to assign role: $_" -Exit $true
}

# Verify the role assignment
try {
    Write-Host "Verifying role assignment..." -ForegroundColor Yellow
    $verifyAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipalId | Where-Object { $_.AppRoleId -eq $AppRole.Id -and $_.ResourceId -contains $GraphServicePrincipal.Id }
   
    if ($null -eq $verifyAssignment) {
        Write-Warning "Role assignment verification failed. The role may not have been assigned correctly."
    }
    else {
        Write-Host "Role assignment verification successful." -ForegroundColor Green
        Write-Host "Role Assignment ID: $($verifyAssignment.Id)" -ForegroundColor Green
    }
}
catch {
    Write-Warning "Error verifying role assignment: $_"
}

Write-Host "Script completed." -ForegroundColor Green
