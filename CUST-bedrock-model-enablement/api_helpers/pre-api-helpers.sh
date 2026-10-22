#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-bedrock-model-enablement / pre-api-helpers.sh
#
# Pre-checks (no mutations):
#   * AWS CLI must be >= 2.27.42 for the bedrock model-access sub-commands
#   * report whether the Anthropic use-case form is already on file
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

cli_supports_model_access() {
  aws bedrock get-foundation-model-availability help >/dev/null 2>&1
}

check_cli() {
  if cli_supports_model_access; then
    log_ok "AWS CLI supports bedrock model-access commands ($(aws --version 2>&1))"
  else
    log_warn "AWS CLI ($(aws --version 2>&1)) predates the bedrock model-access commands (needs >= 2.27.42). Terraform still works; post-helper validation will be skipped."
  fi
}

report_use_case_form() {
  cli_supports_model_access || return 0
  if aws bedrock get-use-case-for-model-access >/dev/null 2>&1; then
    log_info "Anthropic use-case form is already on file for this account/organization."
  else
    log_info "No Anthropic use-case form on file yet; Terraform will submit one (var.submit_use_case_form)."
  fi
}

log_section "Pre-API helpers"
check_cli
case "$(customization_action)" in
  apply) report_use_case_form ;;
  destroy)    log_info "Destroy deletes the model agreements; the use-case form cannot be deleted." ;;
esac
