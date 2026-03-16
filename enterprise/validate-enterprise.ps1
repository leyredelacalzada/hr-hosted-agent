# Enterprise Architecture Validation Script
# Proves all 3 enterprise pillars are correctly deployed:
#   ✅ Customer-Managed Keys (CMK)
#   ✅ Keyless Auth (Managed Identity only — no API keys)
#   ✅ Private Endpoints (no public network access)
#
# Usage:
#   .\validate-enterprise.ps1 -ResourceGroup "rg-hr-agent-enterprise"

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup
)

$ErrorActionPreference = "Stop"
$pass = 0
$fail = 0
$warn = 0

function Check([string]$Name, [bool]$Condition, [string]$FailMsg = "") {
    if ($Condition) {
        Write-Host "  ✅ $Name" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  ❌ $Name — $FailMsg" -ForegroundColor Red
        $script:fail++
    }
}

function Warn([string]$Name, [string]$Msg) {
    Write-Host "  ⚠️  $Name — $Msg" -ForegroundColor Yellow
    $script:warn++
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host " Enterprise Architecture Validation" -ForegroundColor Cyan
Write-Host " Resource Group: $ResourceGroup" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

# -----------------------------------------------------------------------
# Discover resources
# -----------------------------------------------------------------------
Write-Host "Discovering resources..." -ForegroundColor Yellow

$keyVault = az keyvault list -g $ResourceGroup --query "[0]" -o json | ConvertFrom-Json
$storage = az storage account list -g $ResourceGroup --query "[0]" -o json | ConvertFrom-Json
$aiServices = az cognitiveservices account list -g $ResourceGroup --query "[0]" -o json | ConvertFrom-Json
$search = az search service list -g $ResourceGroup --query "[0]" -o json | ConvertFrom-Json
$acr = az acr list -g $ResourceGroup --query "[0]" -o json | ConvertFrom-Json
$vnet = az network vnet list -g $ResourceGroup --query "[0]" -o json | ConvertFrom-Json
$privateEndpoints = az network private-endpoint list -g $ResourceGroup -o json | ConvertFrom-Json
$identity = az identity list -g $ResourceGroup --query "[0]" -o json | ConvertFrom-Json

Write-Host "  Found: Key Vault=$($keyVault.name), Storage=$($storage.name), AI Services=$($aiServices.name)"
Write-Host "  Found: Search=$($search.name), ACR=$($acr.name), VNET=$($vnet.name)"
Write-Host "  Found: Managed Identity=$($identity.name)"
Write-Host "  Found: $($privateEndpoints.Count) private endpoints`n"

# =======================================================================
# PILLAR 1: PRIVATE ENDPOINTS (no public network access)
# =======================================================================
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
Write-Host " PILLAR 1: Private Endpoints" -ForegroundColor Magenta
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Magenta

# VNET exists
Check "VNET exists" ($null -ne $vnet) "No VNET found"

# Private endpoints count (expect: KV + Storage Blob + Storage File + AI Services + AI Search + ACR = 6)
Check "At least 6 private endpoints deployed" ($privateEndpoints.Count -ge 6) "Found only $($privateEndpoints.Count)"

# List all PEs
Write-Host "`n  Private Endpoints:" -ForegroundColor Gray
foreach ($pe in $privateEndpoints) {
    $target = $pe.privateLinkServiceConnections[0].groupIds -join ","
    Write-Host "    🔒 $($pe.name) → $target" -ForegroundColor Gray
}
Write-Host ""

# Public network access disabled on each service
$kvNetworkDefault = $keyVault.properties.networkAcls.defaultAction
Check "Key Vault — network default action: Deny" ($kvNetworkDefault -eq "Deny") "Got: $kvNetworkDefault"

Check "Storage — public network access: Disabled" ($storage.publicNetworkAccess -eq "Disabled") "Got: $($storage.publicNetworkAccess)"

$aiPub = $aiServices.properties.publicNetworkAccess
Check "AI Services — public network access: Disabled" ($aiPub -eq "Disabled") "Got: $aiPub"

$searchPub = $search.properties.publicNetworkAccess
Check "AI Search — public network access: Disabled" ($searchPub -eq "disabled") "Got: $searchPub"

Check "ACR — public network access: Disabled" ($acr.publicNetworkAccess -eq "Disabled") "Got: $($acr.publicNetworkAccess)"

# Private DNS zones
$dnsZones = az network private-dns zone list -g $ResourceGroup -o json | ConvertFrom-Json
Write-Host "`n  Private DNS Zones ($($dnsZones.Count)):" -ForegroundColor Gray
foreach ($zone in $dnsZones) {
    Write-Host "    🌐 $($zone.name)" -ForegroundColor Gray
}
Check "`nAt least 7 private DNS zones" ($dnsZones.Count -ge 7) "Found $($dnsZones.Count)"

# =======================================================================
# PILLAR 2: KEYLESS AUTH (Managed Identity only — no API keys)
# =======================================================================
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
Write-Host " PILLAR 2: Keyless Auth (Managed Identity Only)" -ForegroundColor Magenta
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Magenta

# User-Assigned MI exists
Check "User-Assigned Managed Identity exists" ($null -ne $identity) "No UAMI found"

# Key Vault — RBAC authorization
Check "Key Vault — RBAC authorization enabled (no access policies)" ($keyVault.properties.enableRbacAuthorization -eq $true) "enableRbacAuthorization is not true"

# AI Services — local auth disabled
$aiLocalAuth = $aiServices.properties.disableLocalAuth
Check "AI Services — local auth disabled (no API keys)" ($aiLocalAuth -eq $true) "disableLocalAuth=$aiLocalAuth"

# Try to list AI Services keys — should fail
Write-Host "  Testing: Attempting to retrieve AI Services keys (should fail)..." -ForegroundColor Gray
$keyResult = az cognitiveservices account keys list -g $ResourceGroup -n $aiServices.name 2>&1
$keyFailed = $keyResult -match "error|cannot|disabled|forbidden|not allowed"
Check "AI Services — key retrieval blocked" $keyFailed "Keys are still accessible!"

# AI Search — local auth disabled
$searchLocalAuth = $search.properties.disableLocalAuth
Check "AI Search — local auth disabled (no API/query keys)" ($searchLocalAuth -eq $true) "disableLocalAuth=$searchLocalAuth"

# Storage — shared key access disabled
Check "Storage — shared key access disabled" ($storage.allowSharedKeyAccess -eq $false) "allowSharedKeyAccess=$($storage.allowSharedKeyAccess)"

# ACR — admin user disabled
Check "ACR — admin user disabled" ($acr.adminUserEnabled -eq $false) "adminUserEnabled=$($acr.adminUserEnabled)"

# RBAC role assignments on the MI
Write-Host "`n  Role assignments for MI ($($identity.principalId)):" -ForegroundColor Gray
$roles = az role assignment list --assignee $identity.principalId -g $ResourceGroup --query "[].{Role:roleDefinitionName, Scope:scope}" -o json | ConvertFrom-Json
foreach ($role in $roles) {
    $scopeShort = ($role.Scope -split "/")[-1]
    Write-Host "    🔑 $($role.Role) → $scopeShort" -ForegroundColor Gray
}
Check "`nAt least 5 RBAC role assignments on MI" ($roles.Count -ge 5) "Found $($roles.Count)"

# =======================================================================
# PILLAR 3: CUSTOMER-MANAGED KEYS (CMK)
# =======================================================================
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
Write-Host " PILLAR 3: Customer-Managed Keys (CMK)" -ForegroundColor Magenta
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Magenta

# Key Vault — purge protection (required for CMK)
Check "Key Vault — purge protection enabled" ($keyVault.properties.enablePurgeProtection -eq $true) "enablePurgeProtection is not true"

# Key Vault — soft delete
Check "Key Vault — soft delete enabled" ($keyVault.properties.enableSoftDelete -eq $true) "enableSoftDelete is not true"

# CMK key exists
$keys = az keyvault key list --vault-name $keyVault.name -o json 2>&1 | ConvertFrom-Json
$cmkKey = $keys | Where-Object { $_.name -eq "cmk-encryption-key" }
Check "CMK key 'cmk-encryption-key' exists in Key Vault" ($null -ne $cmkKey) "Key not found"

if ($cmkKey) {
    Write-Host "    🔐 Key URI: $($cmkKey.kid)" -ForegroundColor Gray
}

# Storage — CMK encryption
$storageEncryption = $storage.encryption.keySource
Check "Storage — encryption key source: Microsoft.Keyvault" ($storageEncryption -eq "Microsoft.Keyvault") "Got: $storageEncryption"

# AI Services — CMK encryption
$aiEncryption = $aiServices.properties.encryption.keySource
Check "AI Services — encryption key source: Microsoft.KeyVault" ($aiEncryption -eq "Microsoft.KeyVault") "Got: $aiEncryption"

# ACR — CMK encryption
$acrEncryption = $acr.encryption.status
Check "ACR — CMK encryption enabled" ($acrEncryption -eq "enabled") "Got: $acrEncryption"

# AI Search — CMK enforcement
$searchCmk = $search.properties.encryptionWithCmk.enforcement
Check "AI Search — CMK enforcement enabled" ($searchCmk -eq "Enabled") "Got: $searchCmk"

# =======================================================================
# SUMMARY
# =======================================================================
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host " VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  ✅ PASSED: $pass" -ForegroundColor Green
if ($warn -gt 0) { Write-Host "  ⚠️  WARNINGS: $warn" -ForegroundColor Yellow }
if ($fail -gt 0) { Write-Host "  ❌ FAILED: $fail" -ForegroundColor Red }
Write-Host ""

if ($fail -eq 0) {
    Write-Host "  🎉 ALL CHECKS PASSED — Enterprise architecture verified!" -ForegroundColor Green
    Write-Host "  Your deployment has:" -ForegroundColor Green
    Write-Host "    🔒 Private endpoints on all services (zero public exposure)" -ForegroundColor Green
    Write-Host "    🔑 Managed identity auth only (zero API keys)" -ForegroundColor Green
    Write-Host "    🔐 Customer-managed encryption keys (your key, your control)" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  $fail check(s) failed. Review the output above." -ForegroundColor Red
}
Write-Host ""
