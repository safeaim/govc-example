#!/usr/bin/env bash
# Installs k3s and all platform components:
#   Argo Events, Argo Workflows, Kyverno, MinIO
# Then applies all manifests under k8s/.
#
# Usage (from repo root):
#   chmod +x k8s/install.sh && sudo k8s/install.sh
#
# After install, kubeconfig is at /etc/rancher/k3s/k3s.yaml
# Export it:   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARGO_EVENTS_VERSION="v1.9.5"
ARGO_WORKFLOWS_VERSION="v3.6.4"
KYVERNO_VERSION="v1.13.4"

info()  { echo "[INFO]  $*"; }
die()   { echo "[ERROR] $*" >&2; exit 1; }

wait_for_ns() {
  local ns="$1"
  info "Waiting for namespace $ns..."
  until kubectl get ns "$ns" &>/dev/null; do sleep 2; done
}

wait_for_crds() {
  local crd="$1"
  info "Waiting for CRD $crd..."
  until kubectl get crd "$crd" &>/dev/null; do sleep 3; done
}

# ── k3s ─────────────────────────────────────────────────────────────────────
info "Installing k3s..."
if ! command -v k3s &>/dev/null; then
  curl -sfL https://get.k3s.io | sh -s - \
    --write-kubeconfig-mode 644 \
    --disable traefik          # we don't need traefik for this setup
else
  info "k3s already installed, skipping."
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

info "Waiting for k3s node to be Ready..."
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 3; done
info "k3s is ready."

# ── Argo Workflows ───────────────────────────────────────────────────────────
info "Installing Argo Workflows ${ARGO_WORKFLOWS_VERSION}..."
kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo \
  -f "https://github.com/argoproj/argo-workflows/releases/download/${ARGO_WORKFLOWS_VERSION}/install.yaml"

# Allow workflows to use the default SA for submitting (dev convenience)
kubectl create clusterrolebinding argo-default-admin \
  --clusterrole=admin \
  --serviceaccount=argo:default \
  --dry-run=client -o yaml | kubectl apply -f -

# ── Argo Events ─────────────────────────────────────────────────────────────
info "Installing Argo Events ${ARGO_EVENTS_VERSION}..."
kubectl create namespace argo-events --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-events \
  -f "https://github.com/argoproj/argo-events/releases/download/${ARGO_EVENTS_VERSION}/install.yaml"
kubectl apply -n argo-events \
  -f "https://github.com/argoproj/argo-events/releases/download/${ARGO_EVENTS_VERSION}/sensors-rbac.yaml"

# ── Kyverno ──────────────────────────────────────────────────────────────────
info "Installing Kyverno ${KYVERNO_VERSION}..."
kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -
kubectl apply \
  -f "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/install.yaml"

# ── Wait for controllers ──────────────────────────────────────────────────────
info "Waiting for Argo Workflows controller..."
kubectl rollout status deployment/workflow-controller -n argo --timeout=120s

info "Waiting for Argo Events controller..."
kubectl rollout status deployment/argo-events-controller-manager -n argo-events --timeout=120s

info "Waiting for Kyverno..."
kubectl rollout status deployment/kyverno-admission-controller -n kyverno --timeout=120s

wait_for_crds "clusterpolicies.kyverno.io"
wait_for_crds "eventbus.argoproj.io"
wait_for_crds "eventsources.argoproj.io"
wait_for_crds "sensors.argoproj.io"
wait_for_crds "workflowtemplates.argoproj.io"

# ── Apply our manifests ───────────────────────────────────────────────────────
info "Applying platform manifests..."

kubectl apply -f "${SCRIPT_DIR}/minio/"
kubectl apply -f "${SCRIPT_DIR}/argo-workflows/"
kubectl apply -f "${SCRIPT_DIR}/argo-events/"
kubectl apply -f "${SCRIPT_DIR}/kyverno/"

info ""
info "════════════════════════════════════════════════════"
info " Platform is up!"
info ""
info " Argo Workflows UI:"
info "   kubectl -n argo port-forward svc/argo-server 2746:2746"
info "   → https://localhost:2746"
info ""
info " Argo Events webhook (for Backstage):"
info "   kubectl -n argo-events port-forward svc/backstage-webhook-eventsource-svc 12000:12000"
info "   → http://localhost:12000/namespace-request"
info ""
info " MinIO console:"
info "   kubectl -n minio port-forward svc/minio-console 9001:9001"
info "   → http://localhost:9001  (admin / changeme123)"
info "════════════════════════════════════════════════════"
