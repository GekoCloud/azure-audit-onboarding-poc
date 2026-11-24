// Asigna roles de solo lectura a la Enterprise Application de Claranet en un Management Group.
// Desplegado en el Tenant Root Group cubre todas las suscripciones actuales y futuras.
targetScope = 'managementGroup'

@description('Object ID de la Enterprise Application "Claranet" en TU tenant (Entra ID > Enterprise applications > la app > Object ID). NO es el Application (client) ID.')
param principalId string

@description('IDs de definición de rol a asignar. Por defecto: Reader.')
param roleDefinitionIds array = [
  'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
]

resource assignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in roleDefinitionIds: {
  name: guid(managementGroup().id, principalId, roleId)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: tenantResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    description: 'Claranet - auditoria e inventario (solo lectura)'
  }
}]

output scope string = managementGroup().id
output roleAssignmentIds array = [for (roleId, i) in roleDefinitionIds: assignments[i].id]
