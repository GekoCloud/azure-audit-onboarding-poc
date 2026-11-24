#!/usr/bin/env bash
# Onboarding de un tenant cliente para la app multi-tenant de auditoría/inventario.
# Lo ejecuta un administrador DEL CLIENTE, logado en su propio tenant con az CLI.
#
# Requisitos del operador en el tenant cliente:
#   - Entra ID: Privileged Role Administrator o Global Administrator (para conceder permisos Graph de aplicación)
#   - Azure RBAC: Owner o User Access Administrator en el scope elegido (root MG o suscripciones)
#
# Idempotente: se puede relanzar sin duplicar asignaciones.
set -euo pipefail

APP_ID="9a7f3191-d3ea-457f-bf15-f89ea937f994"
PUBLISHER_TENANT_ID="7acabf71-b3af-4684-8766-596f7c8f64f7"
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"

GRAPH_ROLES="User.ReadBasic.All,Group.Read.All,RoleManagement.Read.All,Application.Read.All"
RBAC_ROLES="Reader"
TENANT_ID=""
SCOPE_MODE=""        # root-mg | subscriptions
SUBSCRIPTIONS=""     # lista separada por comas o "all"
SKIP_GRAPH=false

usage() {
  cat <<EOF
Uso: $0 -t <tenantId> (--root-mg | --subscriptions <id1,id2,...|all>) [opciones]

  -t, --tenant <id>            Tenant ID del cliente (obligatorio)
      --root-mg                Asigna roles RBAC en el Tenant Root Management Group (recomendado)
      --subscriptions <list>   Asigna roles RBAC en suscripciones concretas, o "all" (todas las habilitadas del tenant)
  -g, --graph-roles <list>     Permisos Graph de aplicación (por defecto: ${GRAPH_ROLES})
  -r, --rbac-roles <list>      Roles RBAC (por defecto: ${RBAC_ROLES})
      --skip-graph             No conceder permisos Graph (solo inventario ARM)
  -h, --help
EOF
}

log()  { printf '\033[1;34m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tenant)        TENANT_ID="$2"; shift 2 ;;
    --root-mg)          SCOPE_MODE="root-mg"; shift ;;
    --subscriptions)    SCOPE_MODE="subscriptions"; SUBSCRIPTIONS="$2"; shift 2 ;;
    -g|--graph-roles)   GRAPH_ROLES="$2"; shift 2 ;;
    -r|--rbac-roles)    RBAC_ROLES="$2"; shift 2 ;;
    --skip-graph)       SKIP_GRAPH=true; shift ;;
    -h|--help)          usage; exit 0 ;;
    *)                  usage; die "Argumento desconocido: $1" ;;
  esac
done

[[ -n "$TENANT_ID" ]]  || { usage; die "Falta --tenant"; }
[[ -n "$SCOPE_MODE" ]] || { usage; die "Indica --root-mg o --subscriptions"; }
command -v az >/dev/null || die "Azure CLI (az) no encontrado"

# --- 1. Contexto ------------------------------------------------------------
CURRENT_TENANT=$(az account show --query tenantId -o tsv 2>/dev/null || true)
[[ "$CURRENT_TENANT" == "$TENANT_ID" ]] || \
  die "Sesión az en tenant '${CURRENT_TENANT:-ninguno}'. Ejecuta: az login --tenant $TENANT_ID"
[[ "$TENANT_ID" != "$PUBLISHER_TENANT_ID" ]] || die "Este es el tenant publicador, no un tenant cliente"

# --- 2. Service principal (Enterprise Application) -------------------------
SP_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv)
if [[ -z "$SP_ID" ]]; then
  log "Creando Enterprise Application para appId $APP_ID"
  SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
else
  log "Enterprise Application ya existe (objectId $SP_ID)"
fi

OWNER_TENANT=$(az ad sp show --id "$SP_ID" --query appOwnerOrganizationId -o tsv)
[[ "$OWNER_TENANT" == "$PUBLISHER_TENANT_ID" ]] || \
  die "El SP pertenece al tenant '$OWNER_TENANT', esperado '$PUBLISHER_TENANT_ID'. Abortando."

# --- 3. Permisos Microsoft Graph (application) -----------------------------
if [[ "$SKIP_GRAPH" == false ]]; then
  GRAPH_SP_ID=$(az ad sp list --filter "appId eq '$GRAPH_APP_ID'" --query "[0].id" -o tsv)
  [[ -n "$GRAPH_SP_ID" ]] || die "No se encontró el SP de Microsoft Graph en el tenant"

  EXISTING=$(az rest --method GET \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_ID/appRoleAssignments" \
    --query "value[?resourceId=='$GRAPH_SP_ID'].appRoleId" -o tsv)

  IFS=',' read -ra ROLES <<< "$GRAPH_ROLES"
  for ROLE in "${ROLES[@]}"; do
    ROLE_ID=$(az ad sp show --id "$GRAPH_SP_ID" \
      --query "appRoles[?value=='$ROLE' && contains(allowedMemberTypes, 'Application')].id | [0]" -o tsv)
    [[ -n "$ROLE_ID" ]] || die "Permiso Graph de aplicación desconocido: $ROLE"

    if grep -qx "$ROLE_ID" <<< "$EXISTING"; then
      log "Graph $ROLE ya concedido"
      continue
    fi
    log "Concediendo Graph $ROLE (admin consent)"
    az rest --method POST \
      --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_ID/appRoleAssignments" \
      --headers "Content-Type=application/json" \
      --body "{\"principalId\":\"$SP_ID\",\"resourceId\":\"$GRAPH_SP_ID\",\"appRoleId\":\"$ROLE_ID\"}" \
      -o none
  done
fi

# --- 4. Azure RBAC ---------------------------------------------------------
SCOPES=()
if [[ "$SCOPE_MODE" == "root-mg" ]]; then
  SCOPES+=("/providers/Microsoft.Management/managementGroups/$TENANT_ID")
else
  if [[ "$SUBSCRIPTIONS" == "all" ]]; then
    SUBS=()
    while IFS= read -r S; do [[ -n "$S" ]] && SUBS+=("$S"); done < <(az account list --all \
      --query "[?tenantId=='$TENANT_ID' && state=='Enabled'].id" -o tsv)
  else
    IFS=',' read -ra SUBS <<< "$SUBSCRIPTIONS"
  fi
  [[ ${#SUBS[@]} -gt 0 ]] || die "No hay suscripciones a las que asignar roles"
  for S in "${SUBS[@]}"; do SCOPES+=("/subscriptions/$S"); done
fi

assign_role() {
  local role="$1" scope="$2" attempt
  local count
  count=$(az role assignment list --assignee "$SP_ID" --role "$role" --scope "$scope" \
    --query "length(@)" -o tsv 2>/dev/null || echo 0)
  if [[ "$count" -gt 0 ]]; then
    log "RBAC $role ya asignado en $scope"
    return 0
  fi
  # Reintentos: un SP recién creado puede tardar en replicarse
  for attempt in 1 2 3 4 5; do
    if az role assignment create \
        --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
        --role "$role" --scope "$scope" -o none 2>/dev/null; then
      log "RBAC $role asignado en $scope"
      return 0
    fi
    warn "Fallo asignando $role en $scope (intento $attempt/5), reintentando en 15s"
    sleep 15
  done
  die "No se pudo asignar $role en $scope. Revisa permisos (Owner/User Access Administrator)."
}

IFS=',' read -ra RROLES <<< "$RBAC_ROLES"
for SCOPE in "${SCOPES[@]}"; do
  for R in "${RROLES[@]}"; do assign_role "$R" "$SCOPE"; done
done

# --- 5. Resumen (enviar a Claranet; no contiene secretos) -------------------
cat <<EOF

================ Onboarding completado ================
Tenant ID cliente : $TENANT_ID
App (client) ID   : $APP_ID
SP object ID      : $SP_ID
Graph             : $([[ "$SKIP_GRAPH" == true ]] && echo "omitido" || echo "$GRAPH_ROLES")
RBAC              : $RBAC_ROLES
Scopes            :
$(printf '  - %s\n' "${SCOPES[@]}")
=======================================================
EOF
