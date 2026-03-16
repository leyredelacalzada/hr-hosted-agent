// ---------------------------------------------------------------------------
// Storage Account + CMK + Private Endpoints (Blob + File)
//
// CMK encryption with the user-assigned managed identity.
// Shared key access disabled — identity-based auth only.
// Private endpoints for both blob and file.
// ---------------------------------------------------------------------------

param location string
param name string
param tags object = {}

// Networking
param subnetId string
param blobDnsZoneId string
param fileDnsZoneId string

// Identity
param managedIdentityId string
param managedIdentityPrincipalId string

// CMK
param keyVaultUri string
param cmkKeyName string

// ---------------------------------------------------------------------------
// Storage Account
// ---------------------------------------------------------------------------
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false         // Keyless — identity-based auth only
    allowBlobPublicAccess: false
    encryption: {
      keySource: 'Microsoft.Keyvault'
      keyvaultproperties: {
        keyname: cmkKeyName
        keyvaulturi: keyVaultUri
      }
      identity: {
        userAssignedIdentity: managedIdentityId
      }
      services: {
        blob: { enabled: true }
        file: { enabled: true }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// RBAC — MI gets Storage Blob Data Contributor
// ---------------------------------------------------------------------------
resource blobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentityPrincipalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Private Endpoints — Blob
// ---------------------------------------------------------------------------
resource blobPe 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${name}-blob-pe'
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [
      {
        name: '${name}-blob-pe'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [ 'blob' ]
        }
      }
    ]
  }
}

resource blobDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: blobPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: { privateDnsZoneId: blobDnsZoneId }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Private Endpoints — File
// ---------------------------------------------------------------------------
resource filePe 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${name}-file-pe'
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [
      {
        name: '${name}-file-pe'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [ 'file' ]
        }
      }
    ]
  }
}

resource fileDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: filePe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'file'
        properties: { privateDnsZoneId: fileDnsZoneId }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output id string = storageAccount.id
output name string = storageAccount.name
