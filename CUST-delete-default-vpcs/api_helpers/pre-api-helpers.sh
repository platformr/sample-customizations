#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-delete-default-vpcs / pre-api-helpers.sh
#
# apply   : delete the default VPC in every enabled region of the account.
# destroy : nothing. A deleted default VPC is not recreated (see README).
#
# Adapted from the Cloud Foundations on AWS template
#   network/network-default-vpc-deletion/script-network-default-vpc-deletion.sh
# with these changes: no jq dependency, idempotent (regions without a default
# VPC are skipped), per-region failures are reported and do not abort the
# sweep, optional region filter and dry-run.
#
# Per region the order is: detach+delete internet gateways -> delete subnets
# -> delete VPC. Default route tables, NACLs and the default security group
# are removed with the VPC. Anything else inside the VPC (instances, ENIs,
# NAT gateways, endpoints) makes delete-vpc fail with DependencyViolation;
# that region is reported as FAIL and left for a human.
#
# Environment:
#   DEFAULT_VPC_REGIONS   space-separated region list to limit the sweep
#                         (default: every enabled region from describe-regions)
#   DEFAULT_VPC_DRY_RUN   "true" to only report what would be deleted
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

DRY_RUN="${DEFAULT_VPC_DRY_RUN:-false}"

enabled_regions() {
  if [[ -n "${DEFAULT_VPC_REGIONS:-}" ]]; then
    printf '%s' "$DEFAULT_VPC_REGIONS"
  else
    aws ec2 describe-regions --query 'Regions[].RegionName' --output text
  fi
}

default_vpc_id() {
  aws --region "$1" ec2 describe-vpcs --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true
}

# delete_default_vpc <region> -> 0 deleted/absent, 1 failed
delete_default_vpc() {
  local region="$1" vpc_id igw_ids subnet_ids igw subnet rc=0
  vpc_id="$(default_vpc_id "$region")"
  if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
    log_ok "${region}: no default VPC"
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "${region}: would delete default VPC ${vpc_id} (dry run)"
    return 0
  fi
  log_info "${region}: deleting default VPC ${vpc_id}"

  igw_ids="$(aws --region "$region" ec2 describe-internet-gateways \
              --filters "Name=attachment.vpc-id,Values=${vpc_id}" \
              --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || true)"
  for igw in $igw_ids; do
    [[ "$igw" == "None" ]] && continue
    log_info "${region}:   detach + delete internet gateway ${igw}"
    aws --region "$region" ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc_id" || rc=1
    aws --region "$region" ec2 delete-internet-gateway --internet-gateway-id "$igw" || rc=1
  done

  subnet_ids="$(aws --region "$region" ec2 describe-subnets \
                 --filters "Name=vpc-id,Values=${vpc_id}" \
                 --query 'Subnets[].SubnetId' --output text 2>/dev/null || true)"
  for subnet in $subnet_ids; do
    [[ "$subnet" == "None" ]] && continue
    log_info "${region}:   delete subnet ${subnet}"
    aws --region "$region" ec2 delete-subnet --subnet-id "$subnet" || rc=1
  done

  if aws --region "$region" ec2 delete-vpc --vpc-id "$vpc_id"; then
    log_ok "${region}: deleted default VPC ${vpc_id}"
  else
    log_fail "${region}: could not delete ${vpc_id} (resources still attached? see error above)"
    rc=1
  fi
  return $rc
}

sweep_regions() {
  local region total=0 failed=0
  for region in $(enabled_regions); do
    total=$((total + 1))
    delete_default_vpc "$region" || failed=$((failed + 1))
  done
  log_section "Sweep summary"
  log_info "Regions processed: ${total}, regions with failures: ${failed}"
  if [[ "$failed" -gt 0 ]]; then
    log_warn "Some default VPCs could not be deleted; post-api-helpers.sh will report them as remaining."
  fi
}

log_section "Pre-API helpers"
case "$(customization_action)" in
  apply)
    [[ "$DRY_RUN" == "true" ]] && log_warn "DEFAULT_VPC_DRY_RUN=true: reporting only, nothing will be deleted."
    sweep_regions
    ;;
  destroy)
    log_info "Nothing to do: deleted default VPCs are not recreated on destroy (run 'aws ec2 create-default-vpc' per region if you need them back)."
    ;;
esac
