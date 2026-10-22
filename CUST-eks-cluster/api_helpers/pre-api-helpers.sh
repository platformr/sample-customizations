#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-eks-cluster / pre-api-helpers.sh
#
# apply   : sanity checks (CLI present for the Helm provider's exec auth, the
#           region has >= 2 usable AZs, whether the cluster already exists).
# destroy : warn about resources that workloads created through the cluster
#           (ALBs/NLBs, EBS volumes). Terraform does not know about them and
#           they block VPC deletion; delete the workloads first.
# No mutations.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-eks-cluster}"
SSM_PREFIX="/platformr/${CUSTOMIZATION_NAME}"
CLUSTER_NAME="${CLUSTER_NAME:-$(aws ssm get-parameter --name "${SSM_PREFIX}/cluster_name" --query Parameter.Value --output text 2>/dev/null || echo platformr-eks)}"

check_azs() {
  local n
  n="$(aws ec2 describe-availability-zones --filters Name=opt-in-status,Values=opt-in-not-required \
        --query 'length(AvailabilityZones)' --output text 2>/dev/null || echo 0)"
  if [[ "$n" -ge 2 ]]; then log_ok "Region $(aws_region) has ${n} standard AZs"; else log_fail "Region $(aws_region) has ${n} standard AZs; need at least 2"; fi
}

report_cluster() {
  local status
  status="$(aws eks describe-cluster --name "$CLUSTER_NAME" --query cluster.status --output text 2>/dev/null || true)"
  if [[ -n "$status" && "$status" != "None" ]]; then
    log_info "Cluster ${CLUSTER_NAME} already exists (status: ${status}); apply will update in place."
  else
    log_info "Cluster ${CLUSTER_NAME} does not exist yet; apply will create it (control plane takes ~10-15 min)."
  fi
}

warn_orphaned_workload_resources() {
  local vpc_id lbs vols
  vpc_id="$(aws ssm get-parameter --name "${SSM_PREFIX}/vpc_id" --query Parameter.Value --output text 2>/dev/null || true)"
  [[ -n "$vpc_id" && "$vpc_id" != "None" ]] || { log_info "No vpc_id parameter; nothing deployed yet."; return 0; }
  lbs="$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='${vpc_id}'].LoadBalancerName" --output text 2>/dev/null || true)"
  if [[ -n "$lbs" && "$lbs" != "None" ]]; then
    log_warn "Load balancers still exist in ${vpc_id}: ${lbs}"
    log_warn "They were created by Kubernetes Ingress/Service objects. Delete those workloads first or terraform destroy will fail on the VPC."
  else
    log_ok "No load balancers left in ${vpc_id}"
  fi
  vols="$(aws ec2 describe-volumes --filters "Name=tag:eks:eks-cluster-name,Values=${CLUSTER_NAME}" \
           --query 'length(Volumes)' --output text 2>/dev/null || echo 0)"
  if [[ "$vols" != "0" ]]; then
    log_warn "${vols} EBS volume(s) created by PersistentVolumeClaims still exist; they will be orphaned (and billed) after destroy."
  else
    log_ok "No PVC-backed EBS volumes left"
  fi
}

log_section "Pre-API helpers"
case "$(customization_action)" in
  apply)
    check_azs
    report_cluster
    ;;
  destroy)
    warn_orphaned_workload_resources
    ;;
esac
