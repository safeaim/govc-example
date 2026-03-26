#!/usr/bin/env bash
# provision-namespace.sh — Triggers the namespace provisioning Argo Workflow
# via the Argo Events webhook. Claude Dispatch can call this directly.
#
# Usage:
#   bash scripts/provision-namespace.sh <namespace> <team> <cpu> <memGi> <minio> <postgres>
#
# Arguments:
#   namespace   Lowercase RFC-1123 name, e.g. team-alpha
#   team        RBAC Group name, e.g. alpha
#   cpu         Integer CPU cores limit (>4 triggers manual approval)
#   memGi       Integer memory limit in Gi (>8 triggers manual approval)
#   minio       true|false — create a MinIO bucket
#   postgres    true|false — deploy a PostgreSQL StatefulSet
#
# Examples:
#   bash scripts/provision-namespace.sh team-alpha alpha 2 4 false true
#   bash scripts/provision-namespace.sh team-ml    ml    8 32 true  true

set -euo pipefail

WEBHOOK_URL="${ARGO_EVENTS_WEBHOOK_URL:-http://localhost:12000/namespace-request}"

usage() {
  sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
  exit 0
}

die() { echo "[ERROR] $*" >&2; exit 1; }

# ── Argument validation ───────────────────────────────────────────────────────
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage
[[ $# -ne 6 ]] && { echo "Expected 6 arguments, got $#"; usage; }

NAMESPACE="$1"
TEAM="$2"
CPU="$3"
MEM_GI="$4"
REQUEST_MINIO="$5"
REQUEST_POSTGRES="$6"

# Namespace: lowercase alphanumeric + hyphens, 2-63 chars
[[ "$NAMESPACE" =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]] \
  || die "Invalid namespace '${NAMESPACE}'. Must match ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$"

# Team: lowercase alphanumeric + hyphens
[[ "$TEAM" =~ ^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]?$ ]] \
  || die "Invalid team '${TEAM}'"

# CPU and memory must be positive integers
[[ "$CPU" =~ ^[1-9][0-9]*$ ]] \
  || die "cpu must be a positive integer, got '${CPU}'"
[[ "$MEM_GI" =~ ^[1-9][0-9]*$ ]] \
  || die "memGi must be a positive integer, got '${MEM_GI}'"

# Boolean flags
[[ "$REQUEST_MINIO" == "true" || "$REQUEST_MINIO" == "false" ]] \
  || die "minio must be 'true' or 'false', got '${REQUEST_MINIO}'"
[[ "$REQUEST_POSTGRES" == "true" || "$REQUEST_POSTGRES" == "false" ]] \
  || die "postgres must be 'true' or 'false', got '${REQUEST_POSTGRES}'"

# ── Policy notice ─────────────────────────────────────────────────────────────
if [[ "$CPU" -gt 4 || "$MEM_GI" -gt 8 ]]; then
  echo "[NOTICE] Requested limits (${CPU} CPU / ${MEM_GI}Gi) exceed policy thresholds."
  echo "         The Argo Workflow will pause for operator approval."
  echo "         To approve:  argo resume <workflow-name> -n argo"
fi

# ── Build payload ─────────────────────────────────────────────────────────────
PAYLOAD=$(cat <<EOF
{
  "namespace":      "${NAMESPACE}",
  "team":           "${TEAM}",
  "cpuLimit":       "${CPU}",
  "memoryLimit":    "${MEM_GI}Gi",
  "requestMinio":   ${REQUEST_MINIO},
  "requestPostgres": ${REQUEST_POSTGRES}
}
EOF
)

echo "[INFO] Posting to ${WEBHOOK_URL}"
echo "[INFO] Payload: ${PAYLOAD}"

# ── POST to Argo Events webhook ───────────────────────────────────────────────
HTTP_CODE=$(curl -s -o /tmp/provision_response.json -w "%{http_code}" \
  -X POST "${WEBHOOK_URL}" \
  -H 'Content-Type: application/json' \
  -d "${PAYLOAD}")

RESPONSE=$(cat /tmp/provision_response.json)

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "[OK]   Webhook accepted (HTTP ${HTTP_CODE})"
  echo "       Response: ${RESPONSE}"
  echo ""
  echo "Track the workflow:"
  echo "  argo list -n argo"
  echo "  kubectl -n argo port-forward svc/argo-server 2746:2746  → https://localhost:2746"
else
  die "Webhook returned HTTP ${HTTP_CODE}: ${RESPONSE}"
fi
