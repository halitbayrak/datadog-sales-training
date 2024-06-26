@description('a comma-deliminated list of the resource groups where resources will be created.')
param resourceGroups string

@description('the password for the admin user.')
@secure()
param adminPassword string

@description('the prefix that all objects will have upon creation.')
param objectPrefix string = 'dd-training'

@description('location for all resources.')
param location string = resourceGroup().location

@description('the number of webapps to create.')
param webAppCount int = 1

@description('the name of the app service plan.')
param serverFarmName string = 'log-generator-${uniqueString(resourceGroup().id)}-asp'

@description('the sku for the app service plan.')
param sku string = 'Basic'

@description('the sku code for the app service plan.')
param skuCode string = 'B1'

var vnetAddressPrefix = '10.1.0.0/16'
var vmSubnetAddressPrefix = '10.1.0.0/24'
var vmSubnetName = '${objectPrefix}-subnet0'
var bastionSubnetAddressPrefix = '10.1.1.0/26'
var bastionSubnetName = 'AzureBastionSubnet'
var tags = {
  company: 'datadog'
  business_unit: 'sales-training'
  env: 'development'
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: '${objectPrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetAddressPrefix
        }
      }
      {
        name: vmSubnetName
        properties: {
          addressPrefix: vmSubnetAddressPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: '${objectPrefix}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource bastionPublicIP 'Microsoft.Network/publicIPAddresses@2022-07-01' = {
  name: '${objectPrefix}-bastion-ip'
  location: location
  tags: tags
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    name: 'Standard'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2022-07-01' = {
  name: '${objectPrefix}-bastion'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        properties: {
          subnet: {
            id: '${virtualNetwork.id}/subnets/${bastionSubnetName}'
          }
          publicIPAddress: {
            id: bastionPublicIP.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
        name: 'bastion-ipconfig'
      }
    ]
  }
}

var vmSubnet = first(filter(virtualNetwork.properties.subnets, subnet => toLower(subnet.name) == toLower(vmSubnetName)))
module vmCreation './vm.bicep' = [for (rg, i) in split(resourceGroups, ' | '): {
  name: 'vmcreation'
  scope: resourceGroup(rg)
  params: {
    index: i
    objectPrefix: objectPrefix
    subnetId: vmSubnet!.id
    networkSecurityGroupId: networkSecurityGroup.id
    adminPassword: adminPassword
    location: location
    tags: tags
  }
}]

resource serverFarm 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: serverFarmName
  location: location
  tags: tags
  properties: {
    reserved: true
  }
  sku: {
    tier: sku
    name: skuCode
  }
  kind: 'linux'
}

module webApp './webapp.bicep' = [for i in range(0, webAppCount): {
  name: 'webApp-${i}'
  params: {
    location: location
    index: i
    tags: tags
    serverFarmId: serverFarm.id
  }
}]
