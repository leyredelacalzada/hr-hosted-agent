// ---------------------------------------------------------------------------
// Azure Container Registry + CMK + Private Endpoint
//
// Premium SKU (required for CMK + private endpoints).
// Admin user disabled — managed identity only (AcrPull/AcrPush via RBAC).
// ---------------------------------------------------------------------------

param location string
param name string
param tags object = {}

// Networking
param subnetId string
param privateDnsZoneId string

// Identity
param managedIdentityId string
param managedIdentityPrincipalId string
param managedIdentityClientId string

// CMK — ACR accepts the full key URI (unversioned = auto-rotation)
param cmkKeyUri string

// ---------------------------------------------------------------------------
// Container Registry
// ---------------------------------------------------------------------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: 'Premium' }             // Premium required for PE + CMK
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    adminUserEnabled: false             // No admin user — MI only
    publicNetworkAccess: 'Disabled'
    encryption: {
      status: 'enabled'
      keyVaultProperties: {
        keyIdentifier: cmkKeyUri
        identity: managedIdentityClientId
      }
    }
  }
}

// ---------------------------------------------------------------------------
// RBAC — MI gets AcrPull + AcrPush
// ---------------------------------------------------------------------------
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, managedIdentityPrincipalId, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  scope: acr
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalType: 'ServicePrincipal'
  }
}

resource acrPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, managedIdentityPrincipalId, '8311e382-0749-4cb8-b61a-304f252e45ec')
  scope: acr
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
    principalType: 'ServicePrincipal'
  }
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
          privateLinkServiceId: acr.id
          groupIds: [ 'registry' ]
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
        name: 'acr'
        properties: { privateDnsZoneId: privateDnsZoneId }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output id string = acr.id
output loginServer string = acr.properties.loginServer
output name string = acr.name
