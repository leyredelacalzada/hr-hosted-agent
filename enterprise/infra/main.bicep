// =============================================================================
// Enterprise Infrastructure — Hosted Agent + Foundry IQ + MAF Architecture
//
// Deploys the EXACT same architecture as Part 1, but with:
//   🔑 Customer-Managed Keys (CMK) — all data encrypted with YOUR key
//   🔐 Keyless Auth (Managed Identity) — no API keys anywhere
//   🔒 Private Endpoints — no public internet exposure
//
// Usage:
//   az deployment group create \
//     --resource-group <rg-name> \
//     --template-file infra/main.bicep \
//     --parameters prefix=<your-prefix> deployerPrincipalId=<your-object-id>
// =============================================================================

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Prefix for all resource names (3-10 alphanumeric characters)')
@minLength(3)
@maxLength(10)
param prefix string

@description('OpenAI model to deploy')
param modelDeploymentName string = 'gpt-4.1'

@description('AI Search SKU (standard or higher for private endpoints)')
param searchSku string = 'standard'

@description('Object ID of the deployer — needed for Key Vault Crypto Officer role to create the CMK key. Get it with: az ad signed-in-user show --query id -o tsv')
param deployerPrincipalId string = ''

// ---------------------------------------------------------------------------
// Naming — globally unique, within length limits
// ---------------------------------------------------------------------------
var suffix = substring(uniqueString(resourceGroup().id), 0, 8)
var tags = {
  project: 'hr-hosted-agent-enterprise'
  environment: 'enterprise'
}

// ---------------------------------------------------------------------------
// 1. Managed Identity — single identity for all resources
// ---------------------------------------------------------------------------
module managedIdentity 'modules/managed-identity.bicep' = {
  name: 'managed-identity'
  params: {
    location: location
    name: '${prefix}-id-${suffix}'
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// 2. Network — VNET + subnets + private DNS zones
// ---------------------------------------------------------------------------
module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    vnetName: '${prefix}-vnet-${suffix}'
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// 3. Key Vault — CMK source + private endpoint
// ---------------------------------------------------------------------------
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    name: '${prefix}-kv-${suffix}'
    tags: tags
    subnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: network.outputs.keyVaultDnsZoneId
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    deployerPrincipalId: deployerPrincipalId
  }
}

// ---------------------------------------------------------------------------
// 4. Storage — CMK encrypted + private endpoints (blob + file)
// ---------------------------------------------------------------------------
module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    name: toLower(replace('${prefix}st${suffix}', '-', ''))
    tags: tags
    subnetId: network.outputs.privateEndpointSubnetId
    blobDnsZoneId: network.outputs.blobDnsZoneId
    fileDnsZoneId: network.outputs.fileDnsZoneId
    managedIdentityId: managedIdentity.outputs.id
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    keyVaultUri: keyVault.outputs.uri
    cmkKeyName: keyVault.outputs.cmkKeyName
  }
}

// ---------------------------------------------------------------------------
// 5. AI Services (OpenAI) — CMK + model deployment + private endpoint
// ---------------------------------------------------------------------------
module aiServices 'modules/ai-services.bicep' = {
  name: 'ai-services'
  params: {
    location: location
    name: '${prefix}-ai-${suffix}'
    tags: tags
    subnetId: network.outputs.privateEndpointSubnetId
    cognitiveServicesDnsZoneId: network.outputs.cognitiveServicesDnsZoneId
    openaiDnsZoneId: network.outputs.openaiDnsZoneId
    managedIdentityId: managedIdentity.outputs.id
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    managedIdentityClientId: managedIdentity.outputs.clientId
    keyVaultUri: keyVault.outputs.uri
    cmkKeyName: keyVault.outputs.cmkKeyName
    cmkKeyVersion: keyVault.outputs.cmkKeyVersion
    modelDeploymentName: modelDeploymentName
  }
}

// ---------------------------------------------------------------------------
// 6. AI Search — CMK enforcement + private endpoint
// ---------------------------------------------------------------------------
module aiSearch 'modules/ai-search.bicep' = {
  name: 'ai-search'
  params: {
    location: location
    name: '${prefix}-srch-${suffix}'
    tags: tags
    searchSku: searchSku
    subnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: network.outputs.searchDnsZoneId
    managedIdentityId: managedIdentity.outputs.id
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
  }
}

// ---------------------------------------------------------------------------
// 7. Container Registry — CMK + private endpoint
// ---------------------------------------------------------------------------
module acr 'modules/acr.bicep' = {
  name: 'acr'
  params: {
    location: location
    name: toLower(replace('${prefix}acr${suffix}', '-', ''))
    tags: tags
    subnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: network.outputs.acrDnsZoneId
    managedIdentityId: managedIdentity.outputs.id
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    managedIdentityClientId: managedIdentity.outputs.clientId
    cmkKeyUri: keyVault.outputs.cmkKeyUri
  }
}

// =============================================================================
// Outputs — use these values for agent deployment (deploy.py)
// =============================================================================
output aiServicesEndpoint string = aiServices.outputs.endpoint
output projectEndpoint string = aiServices.outputs.foundryEndpoint
output searchEndpoint string = aiSearch.outputs.endpoint
output acrLoginServer string = acr.outputs.loginServer
output managedIdentityClientId string = managedIdentity.outputs.clientId
output keyVaultName string = keyVault.outputs.name
output aiServicesName string = aiServices.outputs.name
output aiSearchName string = aiSearch.outputs.name
output storageAccountName string = storage.outputs.name
