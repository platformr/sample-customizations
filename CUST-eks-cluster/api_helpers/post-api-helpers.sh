#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-eks-cluster / post-api-helpers.sh
#
# apply   : validate the cluster is ACTIVE with Auto Mode compute enabled, the
#           SSM contract is published, and (if kubectl is present) the Helm-
#           installed defaults exist in the cluster.
# destroy : confirm the cluster and the SSM parameters are gone.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-eks-cluster}"
SSM_PREFIX="/platformr/${CUSTOMIZATION_NAME}"
REQUIRED_PARAMS="cluster_name cluster_arn cluster_endpoint cluster_certificate_authority_data cluster_version \
cluster_security_group_id node_security_group_id oidc_provider_arn oidc_issuer_url node_iam_role_arn \
vpc_id vpc_cidr region default_storage_class ingress_class_name ingress_scheme kubeconfig_command \
private_subnet_ids public_subnet_ids availability_zones"

ssm_get() {
  aws ssm get-parameter --name "${SSM_PREFIX}/$1" --query Parameter.Value --output text 2>/dev/null || true
}

validate_ssm_contract() {
  local p v rc=0
  for p in $REQUIRED_PARAMS; do
    v="$(ssm_get "$p")"
    if [[ -n "$v" && "$v" != "None" ]]; then
      case "$p" in
        cluster_certificate_authority_data) log_ok "SSM ${p}: (${#v} chars)" ;;
        *)                                  log_ok "SSM ${p}: ${v}" ;;
      esac
    else
      log_fail "SSM ${p}: missing"; rc=1
    fi
  done
  return $rc
}

validate_cluster() {
  local name status auto version rc=0
  name="$(ssm_get cluster_name)"
  check_nonempty "Cluster name" "$name" || return 1
  status="$(aws eks describe-cluster --name "$name" --query cluster.status --output text 2>/dev/null || true)"
  check_equals "Cluster status" "$status" "ACTIVE" || rc=1
  auto="$(aws eks describe-cluster --name "$name" --query cluster.computeConfig.enabled --output text 2>/dev/null || true)"
  check_equals "Auto Mode compute enabled" "$auto" "True" || rc=1
  version="$(aws eks describe-cluster --name "$name" --query cluster.version --output text 2>/dev/null || true)"
  check_nonempty "Kubernetes version" "$version" || rc=1
  return $rc
}

validate_in_cluster_defaults() {
  if ! command -v kubectl >/dev/null 2>&1; then
    log_warn "kubectl not on build image; skipping in-cluster checks (StorageClass/IngressClass/metrics-server)."
    return 0
  fi
  local name kcfg sc ic ms
  name="$(ssm_get cluster_name)"
  kcfg="$(mktemp)"
  if ! aws eks update-kubeconfig --name "$name" --kubeconfig "$kcfg" >/dev/null 2>&1; then
    log_warn "Could not build kubeconfig for ${name}; skipping in-cluster checks."
    rm -f "$kcfg"; return 0
  fi
  sc="$(kubectl --kubeconfig "$kcfg" get storageclass "$(ssm_get default_storage_class)" -o jsonpath='{.metadata.name}' 2>/dev/null || true)"
  check_nonempty "StorageClass $(ssm_get default_storage_class)" "$sc" || true
  ic="$(kubectl --kubeconfig "$kcfg" get ingressclass "$(ssm_get ingress_class_name)" -o jsonpath='{.metadata.name}' 2>/dev/null || true)"
  check_nonempty "IngressClass $(ssm_get ingress_class_name)" "$ic" || true
  ms="$(kubectl --kubeconfig "$kcfg" -n kube-system get deploy metrics-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  if [[ -n "$ms" && "$ms" != "0" ]]; then log_ok "metrics-server ready replicas: ${ms}"; else log_warn "metrics-server not ready yet (or not installed)"; fi
  rm -f "$kcfg"
}

validate_removed() {
  local name
  name="${CLUSTER_NAME:-platformr-eks}"
  if aws eks describe-cluster --name "$name" >/dev/null 2>&1; then
    log_fail "Cluster ${name} still exists"
  else
    log_ok "Cluster ${name} removed"
  fi
  if [[ -z "$(ssm_get cluster_name)" || "$(ssm_get cluster_name)" == "None" ]]; then
    log_ok "SSM contract parameters removed"
  else
    log_fail "SSM parameters under ${SSM_PREFIX} still present"
  fi
}

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    log_info "Validating EKS cluster..."
    validate_cluster             || true
    validate_ssm_contract        || true
    validate_in_cluster_defaults || true
    ;;
  destroy)
    validate_removed || true
    ;;
esac
