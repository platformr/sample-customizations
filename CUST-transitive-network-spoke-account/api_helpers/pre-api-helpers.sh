#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-transitive-network-spoke-account / pre-api-helpers.sh
#
# apply   : verify the hub is reachable through RAM before Terraform runs:
#             * no PENDING RAM invitations (org sharing off => must accept)
#             * the hub's TGW share is ACTIVE in every spoke region
#             * the hub's IPAM pool share is ACTIVE in the hub home region
# destroy : warn about workload ENIs still in the spoke VPCs (block deletion).
# No mutations.
#
# Environment (keep in sync with variables.tf for the FIRST apply; afterwards
# values come from the SSM contract):
#   SPOKE_REGIONS     space-separated spoke regions   (default: us-east-1)
#   HUB_NAME_PREFIX   hub name_prefix                  (default: network-hub)
#   HUB_HOME_REGION   hub home region                  (default: us-east-1)
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-transitive-network-spoke-account}"
SSM_PREFIX="/platformr/${CUSTOMIZATION_NAME}"

ssm_get() { aws ssm get-parameter --name "${SSM_PREFIX}/$1" --query Parameter.Value --output text 2>/dev/null || true; }

SPOKE_REGIONS="${SPOKE_REGIONS:-$(ssm_get regions | tr ',' ' ')}"; SPOKE_REGIONS="${SPOKE_REGIONS:-us-east-1}"
HUB_NAME_PREFIX="${HUB_NAME_PREFIX:-$(ssm_get hub_name_prefix)}"; HUB_NAME_PREFIX="${HUB_NAME_PREFIX:-network-hub}"
HUB_HOME_REGION="${HUB_HOME_REGION:-$(ssm_get hub_home_region)}"; HUB_HOME_REGION="${HUB_HOME_REGION:-us-east-1}"
[[ "$SPOKE_REGIONS" == "None" ]] && SPOKE_REGIONS="us-east-1"
[[ "$HUB_NAME_PREFIX" == "None" ]] && HUB_NAME_PREFIX="network-hub"
[[ "$HUB_HOME_REGION" == "None" ]] && HUB_HOME_REGION="us-east-1"

share_status() { # <region> <share-name>
  aws --region "$1" ram get-resource-shares --resource-owner OTHER-ACCOUNTS --name "$2" \
    --query 'resourceShares[0].status' --output text 2>/dev/null || true
}

check_pending_invitations() {
  local r pending
  for r in $SPOKE_REGIONS $HUB_HOME_REGION; do
    pending="$(aws --region "$r" ram get-resource-share-invitations \
                --query "resourceShareInvitations[?status=='PENDING'].resourceShareName" --output text 2>/dev/null || true)"
    if [[ -n "$pending" && "$pending" != "None" ]]; then
      log_fail "${r}: PENDING RAM invitations: ${pending}. Enable RAM sharing with Organizations in the management account, or accept them (aws ram accept-resource-share-invitation)."
    fi
  done
}

check_hub_shares() {
  local r status rc=0
  for r in $SPOKE_REGIONS; do
    status="$(share_status "$r" "${HUB_NAME_PREFIX}-tgw-${r}")"
    check_equals "${r}: hub TGW share '${HUB_NAME_PREFIX}-tgw-${r}'" "$status" "ACTIVE" || rc=1
  done
  status="$(share_status "$HUB_HOME_REGION" "${HUB_NAME_PREFIX}-ipam-pools")"
  check_equals "${HUB_HOME_REGION}: hub IPAM pool share '${HUB_NAME_PREFIX}-ipam-pools'" "$status" "ACTIVE" || rc=1
  if [[ $rc -ne 0 ]]; then
    log_fail "Hub not visible. Apply CUST-transitive-network-hub-account in the networking account first and make sure this account is a principal of its shares. terraform apply will fail."
  fi
  return $rc
}

warn_workload_enis() {
  local r vpc enis
  for r in $SPOKE_REGIONS; do
    vpc="$(ssm_get "${r}/vpc_id")"
    [[ -n "$vpc" && "$vpc" != "None" ]] || continue
    enis="$(aws --region "$r" ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${vpc}" \
             --query "length(NetworkInterfaces[?InterfaceType!='transit_gateway'])" --output text 2>/dev/null || echo "?")"
    if [[ "$enis" != "0" ]]; then
      log_warn "${r}: ${vpc} still has ${enis} workload network interface(s); delete the workloads first or VPC deletion fails."
    else
      log_ok "${r}: ${vpc} has no workload network interfaces"
    fi
  done
}

log_section "Pre-API helpers"
case "$(customization_action)" in
  apply)
    check_pending_invitations
    check_hub_shares || true
    ;;
  destroy)
    warn_workload_enis
    ;;
esac
