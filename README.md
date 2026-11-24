# Alta de cliente: acceso de solo lectura para Claranet

Este proceso da a Claranet acceso **de solo lectura** a tu tenant para hacer auditoría e inventario. Tiene dos pasos y se completa en unos 5 minutos. No se crea ninguna credencial en tu tenant, y puedes revocar el acceso en cualquier momento borrando la Enterprise Application.

| Dato | Valor |
|---|---|
| Aplicación | `9a7f3191-d3ea-457f-bf15-f89ea937f994` |
| Tenant publicador | `7acabf71-b3af-4684-8766-596f7c8f64f7` |

## Paso 1: autorizar la aplicación (Global Administrator)

Abre esta URL, sustituyendo `<TU_TENANT_ID>`, y pulsa **Aceptar**:

```
https://login.microsoftonline.com/<TU_TENANT_ID>/adminconsent?client_id=9a7f3191-d3ea-457f-bf15-f89ea937f994&redirect_uri=https%3A%2F%2Fgithub.com%2FGekoCloud%2Fazure-audit-onboarding-poc
```

Esto crea la Enterprise Application en tu tenant y concede estos permisos de Microsoft Graph:

- `User.ReadBasic.All`: perfil básico de usuarios
- `Group.Read.All`: grupos y pertenencias
- `RoleManagement.Read.All`: roles de Entra ID y sus asignaciones
- `Application.Read.All`: app registrations y service principals

A continuación, ve a **Entra ID > Enterprise applications**, busca la aplicación y copia su **Object ID**. Lo necesitarás en el paso 2.

> ⚠️ Necesitas el **Object ID**, no el *Application (client) ID*.

## Paso 2: conceder el rol Reader en Azure (Owner / User Access Administrator)

Elige **una** de las dos opciones.

### Opción A: todo el tenant (recomendada)
Asigna el rol en el *Tenant Root Group*, así cubre todas las suscripciones, también las que se creen en el futuro. En el formulario, selecciona como Management Group el Tenant Root Group.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FGekoCloud%2Fazure-audit-onboarding-poc%2Fmain%2Ftemplates%2Fmanagementgroup-reader%2Fazuredeploy.json)

> Para desplegar en el Tenant Root Group, normalmente hay que [elevar acceso](https://learn.microsoft.com/azure/role-based-access-control/elevate-access-global-admin) temporalmente. Quita la elevación al terminar.

### Opción B: suscripción a suscripción
Repite el despliegue una vez por cada suscripción.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FGekoCloud%2Fazure-audit-onboarding-poc%2Fmain%2Ftemplates%2Fsubscription-reader%2Fazuredeploy.json)

Parámetro: `principalId` = el Object ID que copiaste en el paso 1.

## Revocar el acceso

1. Elimina las asignaciones de rol *Reader* de la aplicación, desde *IAM* del Management Group o de cada suscripción.
2. Elimina la Enterprise Application en Entra ID. Esto revoca también los permisos de Graph.

---

## Notas para Claranet (mantenimiento)

- **Fuente**: `*/main.bicep`. El botón solo admite ARM JSON, así que después de cada cambio hay que recompilar:
  `az bicep build -f <dir>/main.bicep --outfile <dir>/azuredeploy.json`
- **Alternativa por script** (CLI, sin portal): ver [`onboarding/`](onboarding/).
- **Publicación**: el repo tiene que ser **público** (raw.githubusercontent.com sin autenticación). Si no puede serlo, usa un Storage Account con contenedor público de solo lectura, o una URL con SAS.
- **Requisitos de la app en el tenant publicador**:
  - `signInAudience = AzureADMultipleOrgs`.
  - `requiredResourceAccess` con los permisos de Graph declarados. Sin eso, el admin consent no concede nada.
  - Un **redirect URI (Web)** registrado igual a `https://github.com/GekoCloud/azure-audit-onboarding-poc`. Sin él, el consentimiento se aplica pero el usuario ve el error AADSTS500113. Una buena opción es que apunte a esta misma página del repo: así el cliente vuelve directamente a los botones del paso 2.
- Los nombres de las asignaciones son deterministas (`guid(scope, principalId, roleId)`), así que relanzar el despliegue es idempotente.
