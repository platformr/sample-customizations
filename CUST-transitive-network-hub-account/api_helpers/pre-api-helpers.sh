#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-transitive-network-hub-account / pre-api-helpers.sh
#
# apply   : prerequisite checks for the NETWORK account (no mutations):
#             * account belongs to an AWS Organization
#             * every hub region is enabled in the account
#             * no foreign IPAM already exists in the home region
#             * reminder of the two prerequisites only the management account
#               can satisfy (RAM org sharing, IPAM delegated admin)
# destroy : warn about spoke attachments and IPAM allocations that will block
#           deletion of the Transit Gateways / pools.
#
# Environment:
#   NETWORK_HUB_REGIONS   space-separated hub regions (default "us-east-1 us-west-2";
#                         keep in sync with var.hub_regions)
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-transitive-network-hub-account}"
SSM_PREFIX="/platformr/${CUSTOMIZATION_NAME}"
HUB_REGIONS="${NETWORK_HUB_REGIONS:-$(aws ssm get-parameter --name "${SSM_PREFIX}/hub_regions" --query Parameter.Value --output text 2>/dev/null | tr ',' ' ' || true)}"
HUB_REGIONS="${HUB_REGIONS:-us-east-1 us-west-2}"

ssm_get() {
  aws ssm get-parameter --name "${SSM_PREFIX}/$1" --query Parameter.Value --output text 2>/dev/null || true
}

check_organization() {
  local arn
  arn="$(aws organizations describe-organization --query Organization.Arn --output text 2>/dev/null || true)"
  check_nonempty "Organization ARN (RAM principal)" "$arn"
}

check_regions_enabled() {
  local enabled r rc=0
  enabled=" $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text | tr '\t' ' ') "
  for r in $HUB_REGIONS; do
    if [[ "$enabled" == *" ${r} "* ]]; then log_ok "Region ${r} is enabled"; else log_fail "Region ${r} is not enabled in this account"; rc=1; fi
  done
  return $rc
}

check_existing_ipam() {
  local ids ours
  ids="$(aws ec2 describe-ipams --query 'Ipams[].IpamId' --output text 2>/dev/null || true)"
  ours="$(ssm_get ipam/id)"
  if [[ -z "$ids" || "$ids" == "None" ]]; then
    log_info "No IPAM exists in $(aws_region) yet; Terraform will create one."
  elif [[ -n "$ours" && "$ids" == *"$ours"* ]]; then
    log_info "IPAM ${ours} already exists (managed by this customization)."
  else
    log_warn "An IPAM (${ids}) already exists in $(aws_region) and is not managed here. Only one IPAM per region is allowed; import it or remove it before apply."
  fi
}

remind_management_account_prereqs() {
  log_info "Prerequisites that must already be done from the ORGANIZATION MANAGEMENT account (cannot be verified from here):"
  log_info "  * aws ram enable-sharing-with-aws-organization"
  log_info "  * aws ec2 enable-ipam-organization-admin-account --delegated-admin-account-id $(aws_account_id)"
  log_info "  Platformr Foundation's networking capability performs both when it provisions the network account."
}

warn_blocking_resources() {
  local r tgw atts pool allocs
  for r in $HUB_REGIONS; do
    tgw="$(ssm_get "transit_gateway/${r}/id")"
    [[ -n "$tgw" && "$tgw" != "None" ]] || continue
    atts="$(aws --region "$r" ec2 describe-transit-gateway-attachments \
             --filters "Name=transit-gateway-id,Values=${tgw}" "Name=state,Values=available,pending" \
             --query "TransitGatewayAttachments[?ResourceType!='peering'].[TransitGatewayAttachmentId,ResourceType,ResourceOwnerId]" \
             --output text 2>/dev/null || true)"
    if [[ -n "$atts" && "$atts" != "None" ]]; then
      log_warn "${r}: ${tgw} still has spoke attachments; terraform destroy will fail until they are removed:"
      printf '%s\n' "$atts" | sed 's/^/         /'
    else
      log_ok "${r}: ${tgw} has no spoke attachments"
    fi
  done
  for pool in $(aws ssm get-parameters-by-path --path "${SSM_PREFIX}/ipam/pool/" --recursive \
                 --query "Parameters[?ends_with(Name, '/id') && contains(Name, '/pool/') && !contains(Name, '/pool/cloud/')].Value" \
                 --output text 2>/dev/null || true); do
    [[ "$pool" == "None" ]] && continue
    allocs="$(aws ec2 get-ipam-pool-allocations --ipam-pool-id "$pool" --query 'length(IpamPoolAllocations)' --output text 2>/dev/null || echo "?")"
    if [[ "$allocs" != "0" ]]; then
      log_warn "IPAM pool ${pool} still has ${allocs} allocation(s) (spoke VPCs); release them before destroy."
    fi
  done
}

log_section "Pre-API helpers"
case "$(customization_action)" in
  apply)
    check_organization      || true
    check_regions_enabled   || true
    check_existing_ipam
    remind_management_account_prereqs
    ;;
  destroy)
    warn_blocking_resources
    ;;
esac
