// ---------------------------------------------------------------------------
// Virtual Network + Private DNS Zones
// Creates the VNET with a private-endpoint subnet and all DNS zones needed
// for private connectivity to Azure services.
// ---------------------------------------------------------------------------

param location string
param vnetName string
param tags object = {}

// ---------------------------------------------------------------------------
// VNET
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Private DNS Zones — one per Azure service that needs a private endpoint
// ---------------------------------------------------------------------------
var dnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'                       // 0 - AI Services
  'privatelink.openai.azure.com'                                  // 1 - OpenAI endpoints
  'privatelink.search.windows.net'                                // 2 - AI Search
  'privatelink.blob.${environment().suffixes.storage}'            // 3 - Storage Blob
  'privatelink.file.${environment().suffixes.storage}'            // 4 - Storage File
  'privatelink.vaultcore.azure.net'                               // 5 - Key Vault
  'privatelink.azurecr.io'                                        // 6 - Container Registry
]

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in dnsZoneNames: {
  name: zone
  location: 'global'
  tags: tags
}]

resource vnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in dnsZoneNames: {
  parent: dnsZones[i]
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output vnetId string = vnet.id
output privateEndpointSubnetId string = vnet.properties.subnets[0].id

output cognitiveServicesDnsZoneId string = dnsZones[0].id
output openaiDnsZoneId string = dnsZones[1].id
output searchDnsZoneId string = dnsZones[2].id
output blobDnsZoneId string = dnsZones[3].id
output fileDnsZoneId string = dnsZones[4].id
output keyVaultDnsZoneId string = dnsZones[5].id
output acrDnsZoneId string = dnsZones[6].id
