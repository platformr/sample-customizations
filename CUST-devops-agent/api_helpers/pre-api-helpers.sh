#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-devops-agent / pre-api-helpers.sh
#
# Checks pre-conditions before Terraform runs:
#   * region is one where AWS DevOps Agent is available
#   * the AWS CLI on the build image knows the `devops-agent` service
# Nothing here mutates the account.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

SUPPORTED_REGIONS="us-east-1 us-west-2 eu-central-1 eu-west-1 ap-southeast-2 ap-northeast-1"

check_region_supported() {
  local region
  region="$(aws_region)"
  if [[ " ${SUPPORTED_REGIONS} " == *" ${region} "* ]]; then
    log_ok "Region ${region} supports AWS DevOps Agent"
  else
    log_fail "Region ${region} does not support AWS DevOps Agent (supported: ${SUPPORTED_REGIONS})"
    log_fail "Terraform will reject var.region; set region to a supported value."
  fi
}

check_cli_support() {
  if aws devops-agent help >/dev/null 2>&1; then
    log_ok "AWS CLI supports 'devops-agent' ($(aws --version 2>&1))"
  else
    log_warn "AWS CLI on this build image does not know 'aws devops-agent' ($(aws --version 2>&1))."
    log_warn "Terraform will still create the agent space, but post-api-helpers.sh cannot associate the account or enable the operator app until the CLI is updated."
  fi
}

log_section "Pre-API helpers"
case "$(customization_action)" in
  apply)
    check_region_supported
    check_cli_support
    ;;
  destroy)
    check_cli_support
    log_info "Deleting the agent space removes its associations and operator app; nothing to do before Terraform."
    ;;
esac
