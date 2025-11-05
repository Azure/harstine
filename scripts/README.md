# Cloud PC Administrator Role Assignment Script

## Overview

This PowerShell script automates the process of assigning CloudPC.ReadWrite.All permissions to the DevCenter / Project Fidalgo service principal in Microsoft Entra ID (formerly Azure AD). This assignment is required to enable the Project Harstine service to manage Cloud PCs within your tenant.

- The script will need to be run by a Global Administrator or Privileged Role Administrator
- The consent prompt will only appear the first time you run the script
- If the role is already assigned, the script will exit successfully

## Prerequisites

### System Requirements

- **PowerShell 7.x (pwsh)** — The script will not run in Windows PowerShell 5.1. Download and install PowerShell 7 from [https://aka.ms/powershell](https://aka.ms/powershell)
- **Azure CLI (`az`)** — Must be installed and available in your PATH. [Install instructions](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?view=azure-cli-latest&pivots=msi)
- **At least one enabled Azure subscription** in the target tenant
- **Permission to install PowerShell modules** (if not already installed)

### Permissions Required

#### Microsoft Entra ID (Graph) Permissions

The script requires the following Microsoft Graph permissions:

- **Administrator permissions** in your Microsoft Entra ID tenant (Global Administrator or Privileged Role Administrator)

The Global Administrator permission will grant you the following:
- **AppRoleAssignment.ReadWrite.All** - To assign application roles
- **Application.Read.All** - To identify the Project Fidalgo and Graph service principals


#### Additional Azure Permissions (Resource Provider Registration)

> **Note:** The following Azure permissions are only required if the Project Fidalgo service principal is not present in your tenant and the script needs to register the Microsoft.DevCenter resource provider. In this case, the script will prompt you to log in to Azure CLI for the correct tenant and to select an Azure subscription.

If this is the case, you must have one of the following Azure roles on the selected subscription:

- **Owner**
- **Contributor**

These roles grant the `Microsoft.Resources/subscriptions/providers/register/action` permission required to register resource providers.

## Usage

1. Open PowerShell 7 (pwsh)
2. Navigate to the folder containing the script
3. Run the script using:

   ```pwsh
   pwsh -File .\Assign-CloudPCAdminRole.ps1
   ```

   or, if already in a PowerShell 7 prompt:

   ```pwsh
   .\Assign-CloudPCAdminRole.ps1
   ```

4. Follow the on-screen prompts to authenticate and select your tenant
5. The script will automatically assign the required role and verify success

## Troubleshooting

If you encounter issues:

- Ensure you have sufficient permissions in your Microsoft Entra ID tenant
- Ensure Azure CLI is installed and available in your PATH
- Ensure you have at least one enabled Azure subscription in the target tenant
- If the script cannot register the Microsoft.DevCenter resource provider, ensure you have the "Owner" or "Contributor" role on the selected Azure subscription. These roles grant the `Microsoft.Resources/subscriptions/providers/register/action` permission required for resource provider registration.
