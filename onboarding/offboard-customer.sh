#!/usr/bin/env bash
# Offboarding: elimina asignaciones RBAC y la Enterprise Application del tenant cliente.
# Lo ejecuta un administrador DEL CLIENTE. Borrar el SP revoca también los permisos Graph.
set -euo pipefail

APP_ID="9a7f3191-d3ea-457f-bf15-f89ea937f994"
TENANT_ID="${1:-}"
[[ -n "$TENANT_ID" ]] || { echo "Uso: $0 <tenantId>"; exit 1; }

CURRENT_TENANT=$(az account show --query tenantId -o tsv 2>/dev/null || true)
[[ "$CURRENT_TENANT" == "$TENANT_ID" ]] || { echo "Ejecuta: az login --tenant $TENANT_ID"; exit 1; }

SP_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv)
[[ -n "$SP_ID" ]] || { echo "La Enterprise Application no existe en este tenant. Nada que hacer."; exit 0; }

# Primero RBAC (si se borra antes el SP quedan asignaciones huérfanas "Unknown")
while IFS= read -r A; do
  [[ -n "$A" ]] || continue
  echo "[+] Eliminando asignación RBAC $A"
  az role assignment delete --ids "$A" -o none
done < <(az role assignment list --assignee "$SP_ID" --all --query "[].id" -o tsv)

echo "[+] Eliminando Enterprise Application $SP_ID"
az ad sp delete --id "$SP_ID"
echo "[+] Offboarding completado"
