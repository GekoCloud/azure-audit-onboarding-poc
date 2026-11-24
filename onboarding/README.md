# Onboarding de clientes — App multi-tenant de auditoría/inventario

| Dato | Valor |
|---|---|
| App (client) ID | `9a7f3191-d3ea-457f-bf15-f89ea937f994` |
| Tenant publicador (Claranet) | `7acabf71-b3af-4684-8766-596f7c8f64f7` |

## Qué concede el cliente

| Ámbito | Permiso | Uso |
|---|---|---|
| Microsoft Graph (application) | `User.ReadBasic.All` | Perfil básico de usuarios |
| Microsoft Graph (application) | `Group.Read.All` | Grupos y pertenencias |
| Microsoft Graph (application) | `RoleManagement.Read.All` | Roles de Entra ID y sus asignaciones |
| Microsoft Graph (application) | `Application.Read.All` | App registrations y service principals |
| Azure RBAC | `Reader` en Tenant Root MG (o suscripciones) | Inventario ARM / Resource Graph |

Acceso de **solo lectura**. No incluye lectura de datos (keys, secrets, blobs) ni escritura.

## Requisitos del administrador del cliente

- Entra ID: **Privileged Role Administrator** o **Global Administrator**.
- Azure: **Owner** o **User Access Administrator** en el scope.
  - Para el Root MG suele ser necesario [elevar acceso](https://learn.microsoft.com/azure/role-based-access-control/elevate-access-global-admin) temporalmente. Quitar la elevación al terminar.
- Azure CLI ≥ 2.50 (vale Azure Cloud Shell).

## Opción A — Script (recomendada)

```bash
az login --tenant <TENANT_ID_CLIENTE>

# Reader en todo el tenant (cubre suscripciones futuras)
./onboard-customer.sh -t <TENANT_ID_CLIENTE> --root-mg

# o solo en suscripciones concretas / todas las actuales
./onboard-customer.sh -t <TENANT_ID_CLIENTE> --subscriptions <sub1>,<sub2>
./onboard-customer.sh -t <TENANT_ID_CLIENTE> --subscriptions all

# Solo ARM, sin Entra ID
./onboard-customer.sh -t <TENANT_ID_CLIENTE> --root-mg --skip-graph
```

El script es idempotente y verifica que la app pertenece al tenant de Claranet antes de conceder nada. Al terminar imprime un resumen (tenant, SP object ID, scopes) que el cliente devuelve a Claranet. **No contiene secretos.**

## Opción B — Portal (consentimiento por URL)

1. El Global Admin abre:
   `https://login.microsoftonline.com/<TENANT_ID_CLIENTE>/adminconsent?client_id=9a7f3191-d3ea-457f-bf15-f89ea937f994`
2. Asigna `Reader` a la Enterprise Application en *Management groups → Tenant Root Group → Access control (IAM)*.

> Requiere que la app tenga declarados los permisos en `requiredResourceAccess` (ver abajo).

## Offboarding

```bash
./offboard-customer.sh <TENANT_ID_CLIENTE>
```

Elimina las asignaciones RBAC y después la Enterprise Application (esto revoca también los permisos Graph).

## Prerrequisitos en el tenant publicador (Claranet)

```bash
az login --tenant 7acabf71-b3af-4684-8766-596f7c8f64f7

# Debe ser multi-tenant
az ad app show --id 9a7f3191-d3ea-457f-bf15-f89ea937f994 --query signInAudience   # AzureADMultipleOrgs

# Declarar permisos (necesario para la opción B / consentimiento por URL)
az ad app permission add --id 9a7f3191-d3ea-457f-bf15-f89ea937f994 \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 97235f07-e226-4f63-ace3-39588e11d3a1=Role 5b567255-7703-4780-807c-7be8301ae99b=Role \
                    c7fbd983-d9aa-4fa7-84b8-17382c103bc4=Role 9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30=Role
```

- **Credencial**: federated identity credential (managed identity) o certificado en Key Vault. Nunca client secrets en repo, pipelines ni logs.
- **Publisher verification** (MPN ID): recomendable antes de ir a producción. Sin ella, muchos tenants bloquean el consentimiento.
- Tokens siempre con authority por tenant: `https://login.microsoftonline.com/<TENANT_ID_CLIENTE>`.
