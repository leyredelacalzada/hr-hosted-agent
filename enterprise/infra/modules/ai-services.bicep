// ---------------------------------------------------------------------------
// Azure AI Services (OpenAI) + Model Deployment + CMK + Private Endpoint
//
// Local auth disabled — managed identity only (no API keys).
// CMK encryption with user-assigned MI.
// Private endpoint with DNS zones for both cognitiveservices and openai domains.
// ---------------------------------------------------------------------------

param location string
param name string
param tags object = {}

@description('Display name for the Foundry project')
param projectName string = 'hr-enterprise-project'

// Networking
param subnetId string
param cognitiveServicesDnsZoneId string
param openaiDnsZoneId string

// Identity
param managedIdentityId string
param managedIdentityPrincipalId string
param managedIdentityClientId string

// CMK
param keyVaultUri string
param cmkKeyName string
param cmkKeyVersion string

// Model
@description('Name of the OpenAI model to deploy (e.g., gpt-4.1)')
param modelDeploymentName string = 'gpt-4.1'

// ---------------------------------------------------------------------------
// AI Services Account
// ---------------------------------------------------------------------------
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true              // No API keys — MI only
    allowProjectManagement: true        // Allow Foundry project creation under this account
    encryption: {
      keySource: 'Microsoft.KeyVault'
      keyVaultProperties: {
        keyName: cmkKeyName
        keyVersion: cmkKeyVersion
        keyVaultUri: keyVaultUri
        identityClientId: managedIdentityClientId
      }
    }
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
}

// ---------------------------------------------------------------------------
// Model Deployment
// ---------------------------------------------------------------------------
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: aiServices
  name: modelDeploymentName
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelDeploymentName
    }
  }
}

// ---------------------------------------------------------------------------
// RBAC — MI gets Cognitive Services OpenAI Contributor
// ---------------------------------------------------------------------------
resource openaiContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, managedIdentityPrincipalId, 'a001fd3d-188f-4b5d-821b-7da978bf7442')
  scope: aiServices
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a001fd3d-188f-4b5d-821b-7da978bf7442')
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
          privateLinkServiceId: aiServices.id
          groupIds: [ 'account' ]
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
        name: 'cognitiveservices'
        properties: { privateDnsZoneId: cognitiveServicesDnsZoneId }
      }
      {
        name: 'openai'
        properties: { privateDnsZoneId: openaiDnsZoneId }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Foundry Project (child of AI Services account)
// ---------------------------------------------------------------------------
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: aiServices
  name: projectName
  location: location
  tags: tags
  properties: {
    displayName: projectName
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output id string = aiServices.id
output endpoint string = aiServices.properties.endpoint
output name string = aiServices.name
output projectName string = project.name
output foundryEndpoint string = 'https://${name}.services.ai.azure.com/api/projects/${project.name}'
