#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-transitive-network-hub-account / post-api-helpers.sh
#
# apply   : validate per hub region that the Transit Gateway is available and
#           shared (RAM share ACTIVE), that inter-region peering attachments
#           are available, that IPAM pools are provisioned and shared, and that
#           the SSM contract is present.
# destroy : confirm the Transit Gateways, IPAM and SSM contract are gone.
#
# Reads everything from the SSM contract written by Terraform.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-transitive-network-hub-account}"
SSM_PREFIX="/platformr/${CUSTOMIZATION_NAME}"

ssm_get() {
  aws ssm get-parameter --name "${SSM_PREFIX}/$1" --query Parameter.Value --output text 2>/dev/null || true
}

hub_regions() { ssm_get hub_regions | tr ',' ' '; }

validate_contract() {
  local p rc=0
  for p in hub_regions environments cloud_cidr organization_arn ipam/id ipam/pool/cloud/id ipam/ram_share_arn; do
    check_nonempty "SSM ${p}" "$(ssm_get "$p")" || rc=1
  done
  return $rc
}

validate_transit_gateways() {
  local r tgw state share status rc=0
  for r in $(hub_regions); do
    tgw="$(ssm_get "transit_gateway/${r}/id")"
    check_nonempty "${r}: SSM transit_gateway id" "$tgw" || { rc=1; continue; }
    state="$(aws --region "$r" ec2 describe-transit-gateways --transit-gateway-ids "$tgw" --query 'TransitGateways[0].State' --output text 2>/dev/null || true)"
    check_equals "${r}: ${tgw} state" "$state" "available" || rc=1
    share="$(ssm_get "transit_gateway/${r}/ram_share_arn")"
    status="$(aws --region "$r" ram get-resource-shares --resource-owner SELF --resource-share-arns "$share" --query 'resourceShares[0].status' --output text 2>/dev/null || true)"
    check_equals "${r}: TGW RAM share status" "$status" "ACTIVE" || rc=1
    check_equals "${r}: in-region SSM transit_gateway_id" "$(aws --region "$r" ssm get-parameter --name "${SSM_PREFIX}/transit_gateway_id" --query Parameter.Value --output text 2>/dev/null || true)" "$tgw" || rc=1
  done
  return $rc
}

validate_peering() {
  local names name key region att state rc=0
  names="$(aws ssm get-parameters-by-path --path "${SSM_PREFIX}/transit_gateway/peering/" --recursive \
            --query 'Parameters[].Name' --output text 2>/dev/null || true)"
  if [[ -z "$names" || "$names" == "None" ]]; then
    log_info "No inter-region peering (single hub region or peering disabled)."
    return 0
  fi
  for name in $names; do
    key="${name#"${SSM_PREFIX}"/transit_gateway/peering/}"; key="${key%/attachment_id}"
    region="${key%%--*}"
    att="$(aws ssm get-parameter --name "$name" --query Parameter.Value --output text 2>/dev/null || true)"
    state="$(aws --region "$region" ec2 describe-transit-gateway-peering-attachments --transit-gateway-attachment-ids "$att" \
              --query 'TransitGatewayPeeringAttachments[0].State' --output text 2>/dev/null || true)"
    check_equals "Peering ${key} (${att}) state" "$state" "available" || rc=1
  done
  return $rc
}

validate_ipam() {
  local ipam state pools pool pstate cstate share status rc=0
  ipam="$(ssm_get ipam/id)"
  state="$(aws ec2 describe-ipams --ipam-ids "$ipam" --query 'Ipams[0].State' --output text 2>/dev/null || true)"
  check_equals "IPAM ${ipam} state" "$state" "create-complete" || rc=1
  pools="$(aws ssm get-parameters-by-path --path "${SSM_PREFIX}/ipam/pool/" --recursive \
            --query "Parameters[?ends_with(Name, '/id')].Value" --output text 2>/dev/null || true)"
  for pool in $pools; do
    [[ "$pool" == "None" ]] && continue
    pstate="$(aws ec2 describe-ipam-pools --ipam-pool-ids "$pool" --query 'IpamPools[0].State' --output text 2>/dev/null || true)"
    cstate="$(aws ec2 get-ipam-pool-cidrs --ipam-pool-id "$pool" --query 'IpamPoolCidrs[0].State' --output text 2>/dev/null || true)"
    if [[ "$pstate" == "create-complete" && "$cstate" == "provisioned" ]]; then
      log_ok "Pool ${pool}: ${pstate}, CIDR ${cstate}"
    else
      log_fail "Pool ${pool}: state=${pstate:-?} cidr=${cstate:-?}"; rc=1
    fi
  done
  share="$(ssm_get ipam/ram_share_arn)"
  status="$(aws ram get-resource-shares --resource-owner SELF --resource-share-arns "$share" --query 'resourceShares[0].status' --output text 2>/dev/null || true)"
  check_equals "IPAM pools RAM share status" "$status" "ACTIVE" || rc=1
  return $rc
}

validate_removed() {
  local r tgw
  for r in ${NETWORK_HUB_REGIONS:-us-east-1 us-west-2}; do
    tgw="$(aws --region "$r" ec2 describe-transit-gateways --filters "Name=state,Values=available,pending,modifying" \
            "Name=tag:customization,Values=${CUSTOMIZATION_NAME}" --query 'TransitGateways[].TransitGatewayId' --output text 2>/dev/null || true)"
    if [[ -z "$tgw" || "$tgw" == "None" ]]; then log_ok "${r}: no hub Transit Gateway remains"; else log_fail "${r}: Transit Gateway still present (${tgw})"; fi
  done
  if [[ -z "$(ssm_get ipam/id)" || "$(ssm_get ipam/id)" == "None" ]]; then
    log_ok "SSM contract removed"
  else
    log_fail "SSM contract under ${SSM_PREFIX} still present"
  fi
}

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    log_info "Validating network hub..."
    validate_contract         || true
    validate_transit_gateways || true
    validate_peering          || true
    validate_ipam             || true
    ;;
  destroy)
    validate_removed || true
    ;;
esac
