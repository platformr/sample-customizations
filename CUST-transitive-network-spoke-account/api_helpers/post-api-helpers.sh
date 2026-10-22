#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-transitive-network-spoke-account / post-api-helpers.sh
#
# apply   : per spoke region, validate the VPC is available, the Transit
#           Gateway attachment is available, the cloud route is active, and
#           the SSM contract (home region + in-region copies) is present.
# destroy : confirm VPCs and the SSM contract are gone.
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

regions() { ssm_get regions | tr ',' ' '; }

validate_region() {
  local r="$1" vpc att rt cidr state rc=0
  vpc="$(ssm_get "${r}/vpc_id")"
  check_nonempty "${r}: SSM vpc_id" "$vpc" || return 1
  state="$(aws --region "$r" ec2 describe-vpcs --vpc-ids "$vpc" --query 'Vpcs[0].State' --output text 2>/dev/null || true)"
  check_equals "${r}: VPC ${vpc} state" "$state" "available" || rc=1
  check_nonempty "${r}: VPC CIDR (from IPAM)" "$(ssm_get "${r}/vpc_cidr")" || rc=1

  att="$(ssm_get "${r}/transit_gateway_attachment_id")"
  state="$(aws --region "$r" ec2 describe-transit-gateway-vpc-attachments --transit-gateway-attachment-ids "$att" \
            --query 'TransitGatewayVpcAttachments[0].State' --output text 2>/dev/null || true)"
  check_equals "${r}: TGW attachment ${att} state" "$state" "available" || rc=1

  rt="$(ssm_get "${r}/private_route_table_id")"
  cidr="$(ssm_get cloud_cidr)"
  state="$(aws --region "$r" ec2 describe-route-tables --route-table-ids "$rt" \
            --query "RouteTables[0].Routes[?DestinationCidrBlock=='${cidr}'].State | [0]" --output text 2>/dev/null || true)"
  check_equals "${r}: route ${cidr} -> TGW state" "$state" "active" || rc=1

  check_equals "${r}: in-region SSM vpc_id" "$(aws --region "$r" ssm get-parameter --name "${SSM_PREFIX}/vpc_id" --query Parameter.Value --output text 2>/dev/null || true)" "$vpc" || rc=1
  check_nonempty "${r}: SSM private_subnet_ids" "$(ssm_get "${r}/private_subnet_ids")" || rc=1
  return $rc
}

validate_removed() {
  local r vpcs
  for r in ${SPOKE_REGIONS:-us-east-1}; do
    vpcs="$(aws --region "$r" ec2 describe-vpcs --filters "Name=tag:customization,Values=${CUSTOMIZATION_NAME}" \
             --query 'Vpcs[].VpcId' --output text 2>/dev/null || true)"
    if [[ -z "$vpcs" || "$vpcs" == "None" ]]; then log_ok "${r}: no spoke VPC remains"; else log_fail "${r}: spoke VPC still present (${vpcs})"; fi
  done
  if [[ -z "$(ssm_get regions)" || "$(ssm_get regions)" == "None" ]]; then log_ok "SSM contract removed"; else log_fail "SSM contract under ${SSM_PREFIX} still present"; fi
}

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    log_info "Validating spoke network..."
    check_nonempty "SSM environment" "$(ssm_get environment)" || true
    for r in $(regions); do validate_region "$r" || true; done
    ;;
  destroy)
    validate_removed || true
    ;;
esac
