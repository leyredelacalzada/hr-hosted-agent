// ---------------------------------------------------------------------------
// Key Vault + CMK Encryption Key + Private Endpoint
//
// RBAC-only (no access policies) — the enterprise way.
// Creates a single RSA-2048 key used as Customer-Managed Key for all services.
// ---------------------------------------------------------------------------

param location string
param name string
param tags object = {}

// Networking
param subnetId string
param privateDnsZoneId string

// Identity
param managedIdentityPrincipalId string

@description('Object ID of the deployer, for Key Vault Crypto Officer role (required to create keys via Bicep)')
param deployerPrincipalId string = ''

// ---------------------------------------------------------------------------
// Key Vault
// ---------------------------------------------------------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true        // RBAC only — no access policies
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true          // Required for CMK
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'           // Allow trusted Azure services (ARM, etc.)
    }
  }
}

// ---------------------------------------------------------------------------
// RBAC — Managed Identity gets "Key Vault Crypto User" (use keys for encrypt/decrypt)
// ---------------------------------------------------------------------------
resource miCryptoUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentityPrincipalId, '12338af0-0e69-4776-bea7-57ae8d297424')
  scope: keyVault
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '12338af0-0e69-4776-bea7-57ae8d297424')
    principalType: 'ServicePrincipal'
  }
}

// Deployer gets "Key Vault Crypto Officer" (manage keys — needed for Bicep to create the CMK key)
resource deployerCryptoOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, '14b46e9e-c2b7-41b4-b07b-48a6ebf60603')
  scope: keyVault
  properties: {
    principalId: deployerPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '14b46e9e-c2b7-41b4-b07b-48a6ebf60603')
    principalType: 'User'
  }
}

// ---------------------------------------------------------------------------
// CMK — RSA-2048 encryption key used by Storage, AI Services, ACR
// ---------------------------------------------------------------------------
resource cmkKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: 'cmk-encryption-key'
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [ 'encrypt', 'decrypt', 'wrapKey', 'unwrapKey' ]
  }
  dependsOn: [ deployerCryptoOfficer ]
}

// ---------------------------------------------------------------------------
// Private Endpoint
// ---------------------------------------------------------------------------
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${name}-pe'
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [
      {
        name: '${name}-pe'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [ 'vault' ]
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'keyvault'
        properties: { privateDnsZoneId: privateDnsZoneId }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output id string = keyVault.id
output uri string = keyVault.properties.vaultUri
output name string = keyVault.name
output cmkKeyName string = cmkKey.name
output cmkKeyUri string = cmkKey.properties.keyUri
output cmkKeyUriWithVersion string = cmkKey.properties.keyUriWithVersion
output cmkKeyVersion string = last(split(cmkKey.properties.keyUriWithVersion, '/'))
