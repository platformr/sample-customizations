#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-delete-default-vpcs / post-api-helpers.sh
#
# apply   : verify no default VPC remains in any enabled region and record the
#           result in SSM next to Terraform's marker parameters:
#             /platformr/CUST-delete-default-vpcs/last_validation_status  PASS|FAIL
#             /platformr/CUST-delete-default-vpcs/last_validation         details
# destroy : remove the two helper-owned validation parameters.
#
# Validation prints [ OK ] / [FAIL] per region and never fails the build.
#
# Environment:
#   DEFAULT_VPC_REGIONS   space-separated region list to limit the check
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-delete-default-vpcs}"
SSM_PREFIX="/platformr/${CUSTOMIZATION_NAME}"

enabled_regions() {
  if [[ -n "${DEFAULT_VPC_REGIONS:-}" ]]; then
    printf '%s' "$DEFAULT_VPC_REGIONS"
  else
    aws ec2 describe-regions --query 'Regions[].RegionName' --output text
  fi
}

REMAINING=""   # space-separated "region:vpc-id" entries
REGIONS_CHECKED=0

validate_no_default_vpcs() {
  local region vpc_id
  for region in $(enabled_regions); do
    REGIONS_CHECKED=$((REGIONS_CHECKED + 1))
    vpc_id="$(aws --region "$region" ec2 describe-vpcs --filters Name=isDefault,Values=true \
               --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "<error>")"
    if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
      log_ok "${region}: no default VPC"
    else
      log_fail "${region}: default VPC still present (${vpc_id})"
      REMAINING="${REMAINING} ${region}:${vpc_id}"
    fi
  done
  [[ -z "$REMAINING" ]]
}

record_validation() {
  local status="$1" detail checked_at
  checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  detail="regions_checked=${REGIONS_CHECKED};remaining=${REMAINING:-none};checked_at=${checked_at}"
  aws ssm put-parameter --name "${SSM_PREFIX}/last_validation_status" --type String --overwrite --value "$status" >/dev/null \
    && log_ok "SSM ${SSM_PREFIX}/last_validation_status = ${status}" \
    || log_warn "Could not write ${SSM_PREFIX}/last_validation_status"
  aws ssm put-parameter --name "${SSM_PREFIX}/last_validation" --type String --overwrite --value "$detail" >/dev/null \
    && log_ok "SSM ${SSM_PREFIX}/last_validation = ${detail}" \
    || log_warn "Could not write ${SSM_PREFIX}/last_validation"
}

remove_validation_params() {
  local p
  for p in last_validation_status last_validation; do
    if aws ssm delete-parameter --name "${SSM_PREFIX}/${p}" >/dev/null 2>&1; then
      log_ok "Removed SSM ${SSM_PREFIX}/${p}"
    else
      log_info "SSM ${SSM_PREFIX}/${p} already absent"
    fi
  done
}

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    log_info "Checking every enabled region for a default VPC..."
    if validate_no_default_vpcs; then
      log_ok "No default VPCs remain in ${REGIONS_CHECKED} region(s)"
      record_validation PASS
    else
      log_fail "Default VPCs remain:${REMAINING}"
      record_validation FAIL
    fi
    ;;
  destroy)
    remove_validation_params
    ;;
esac
