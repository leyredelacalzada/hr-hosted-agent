# Enterprise Infrastructure Deployment Script
# Deploys all Azure resources with CMK + Managed Identity + Private Endpoints
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Contributor + User Access Administrator on the target subscription
#   - Bicep CLI (bundled with Azure CLI)
#
# Usage:
#   .\deploy-infra.ps1 -ResourceGroup "rg-hr-agent-enterprise" -Location "eastus2" -Prefix "hragent"

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [ValidateLength(3, 10)]
    [string]$Prefix,

    [string]$ModelDeploymentName = "gpt-4.1",
    [string]$SearchSku = "standard"
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Enterprise Infrastructure Deployment" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- Get deployer's Object ID (for Key Vault Crypto Officer role) ---
Write-Host "Getting deployer identity..." -ForegroundColor Yellow
$deployerObjectId = az ad signed-in-user show --query id -o tsv
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get deployer identity. Make sure you're logged in with 'az login'."
    exit 1
}
Write-Host "  Deployer Object ID: $deployerObjectId"

# --- Create Resource Group ---
Write-Host "`nCreating resource group '$ResourceGroup' in '$Location'..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location --output none

# --- Deploy Bicep ---
Write-Host "`nDeploying enterprise infrastructure..." -ForegroundColor Yellow
Write-Host "  This creates: VNET, Key Vault (CMK), Storage, AI Services + Foundry Project, AI Search, ACR"
Write-Host "  All with private endpoints, CMK encryption, and managed identity auth."
Write-Host "  This may take 15-30 minutes.`n"

$deploymentName = "enterprise-$((Get-Date).ToString('yyyyMMddHHmmss'))"

$result = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file infra/main.bicep `
    --parameters prefix=$Prefix `
                 deployerPrincipalId=$deployerObjectId `
                 modelDeploymentName=$ModelDeploymentName `
                 searchSku=$SearchSku `
    --name $deploymentName `
    --query "properties.outputs" `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Error "`nDeployment failed. Check the Azure portal for details."
    Write-Host "  Common issues:" -ForegroundColor Yellow
    Write-Host "    - RBAC propagation delay: wait 5 min and retry"
    Write-Host "    - Quota limits: check AI Services and Search quotas in your region"
    Write-Host "    - Name conflicts: try a different prefix"
    exit 1
}

$outputs = $result | ConvertFrom-Json

# --- Display results ---
Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Deployment Complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Resource Summary:" -ForegroundColor Cyan
Write-Host "  Project Endpoint:     $($outputs.projectEndpoint.value)"
Write-Host "  AI Services Endpoint: $($outputs.aiServicesEndpoint.value)"
Write-Host "  Search Endpoint:      $($outputs.searchEndpoint.value)"
Write-Host "  ACR Login Server:     $($outputs.acrLoginServer.value)"
Write-Host "  MI Client ID:         $($outputs.managedIdentityClientId.value)"
Write-Host "  Key Vault:            $($outputs.keyVaultName.value)"

Write-Host "`n--- Next Steps ---" -ForegroundColor Yellow
Write-Host "1. Temporarily enable public access (services deployed with public access disabled):"
Write-Host "   See README.md Step 1.5 for the commands."
Write-Host ""
Write-Host "2. Build & push your container image (cloud build — no Docker needed):"
Write-Host "   az acr build --registry $($outputs.acrLoginServer.value.Split('.')[0]) --image hr-hosted-agent:latest --platform linux/amd64 ."
Write-Host ""
Write-Host "3. Set environment variables and deploy the agent:"
Write-Host "   `$env:AZURE_AI_PROJECT_ENDPOINT = '$($outputs.projectEndpoint.value)'"
Write-Host "   `$env:AZURE_SEARCH_ENDPOINT = '$($outputs.searchEndpoint.value)'"
Write-Host "   `$env:CONTAINER_IMAGE = '$($outputs.acrLoginServer.value)/hr-hosted-agent:latest'"
Write-Host "   python deploy.py"
Write-Host ""
Write-Host "4. Start the agent in the Azure AI Foundry portal."
Write-Host ""
Write-Host "5. Re-disable public access (see README.md Step 5)."
