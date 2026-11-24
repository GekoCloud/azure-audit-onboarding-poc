// Asigna roles de solo lectura a la Enterprise Application de Claranet en VARIAS suscripciones
// con un único despliegue. Se lanza en cualquier suscripción del tenant; cada suscripción
// seleccionada recibe un despliegue anidado (cross-subscription).
// Pensado para usarse con createUiDefinition.json (multiselección + autodetección del Object ID).
targetScope = 'subscription'

@description('Object ID de la Enterprise Application "Claranet" en TU tenant. NO es el Application (client) ID.')
param principalId string

@description('IDs de las suscripciones donde asignar los roles.')
@minLength(1)
param subscriptionIds array

@description('IDs de definición de rol a asignar. Por defecto: Reader.')
param roleDefinitionIds array = [
  'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
]

module perSubscription 'role.bicep' = [for subId in subscriptionIds: {
  name: take('claranet-audit-reader-${subId}', 64)
  scope: subscription(subId)
  params: {
    principalId: principalId
    roleDefinitionIds: roleDefinitionIds
  }
}]

output subscriptions array = subscriptionIds
