// Asignación de roles en una suscripción (módulo invocado por main.bicep).
targetScope = 'subscription'

param principalId string
param roleDefinitionIds array

resource assignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in roleDefinitionIds: {
  name: guid(subscription().id, principalId, roleId)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    description: 'Claranet - auditoria e inventario (solo lectura)'
  }
}]
