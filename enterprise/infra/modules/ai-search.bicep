// ---------------------------------------------------------------------------
// Azure AI Search + CMK Enforcement + Private Endpoint
//
// Local auth disabled — managed identity only (no API keys / query keys).
// CMK enforcement enabled at service level (indexes must use CMK).
// ---------------------------------------------------------------------------

param location string
param name string
param tags object = {}

@description('AI Search SKU — must be standard or higher for private endpoints')
param searchSku string = 'standard'

// Networking
param subnetId string
param privateDnsZoneId string

// Identity
param managedIdentityId string
param managedIdentityPrincipalId string

// ---------------------------------------------------------------------------
// AI Search Service
// ---------------------------------------------------------------------------
resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: { name: searchSku }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    hostingMode: 'default'
    publicNetworkAccess: 'disabled'
    disableLocalAuth: true              // No API keys — MI only
    authOptions: null                   // Explicitly remove key-based auth options
    encryptionWithCmk: {
      enforcement: 'Enabled'            // All new indexes MUST use CMK
    }
    semanticSearch: 'standard'          // Enable semantic search (for knowledge base)
  }
}

// ---------------------------------------------------------------------------
// RBAC — MI gets Search Index Data Reader + Search Service Contributor
// ---------------------------------------------------------------------------
resource searchReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, managedIdentityPrincipalId, '1407120a-92aa-4202-b7e9-c0e197c71c8f')
  scope: searchService
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f')
    principalType: 'ServicePrincipal'
  }
}

resource searchContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, managedIdentityPrincipalId, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  scope: searchService
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
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
          privateLinkServiceId: searchService.id
          groupIds: [ 'searchService' ]
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
        name: 'search'
        properties: { privateDnsZoneId: privateDnsZoneId }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output id string = searchService.id
output endpoint string = 'https://${searchService.name}.search.windows.net'
output name string = searchService.name
