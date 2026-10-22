#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-enforce-imdsv2-on-account / pre-api-helpers.sh
#
# Pre-checks (no mutations):
#   * show current IMDS account defaults for the region
#   * fail loudly if a declarative policy manages them (the account cannot
#     change them; apply would error)
#   * warn if the AWS CLI is too old for --http-tokens-enforced
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

report_current_defaults() {
  local tokens hops enforced managed
  tokens="$(aws ec2 get-instance-metadata-defaults --query AccountLevel.HttpTokens --output text 2>/dev/null || true)"
  hops="$(aws ec2 get-instance-metadata-defaults --query AccountLevel.HttpPutResponseHopLimit --output text 2>/dev/null || true)"
  enforced="$(aws ec2 get-instance-metadata-defaults --query AccountLevel.HttpTokensEnforced --output text 2>/dev/null || true)"
  managed="$(aws ec2 get-instance-metadata-defaults --query ManagedBy --output text 2>/dev/null || true)"
  log_info "Current IMDS defaults in $(aws_region): HttpTokens=${tokens:-<unset>} HopLimit=${hops:-<unset>} Enforced=${enforced:-<unset>} ManagedBy=${managed:-<unset>}"
  if [[ "$managed" == "declarative-policy" ]]; then
    log_fail "IMDS defaults are managed by an Organizations declarative policy; this account cannot modify them and terraform apply will fail."
  fi
}

check_cli_supports_enforced() {
  if aws ec2 modify-instance-metadata-defaults help 2>/dev/null | grep -q -- '--http-tokens-enforced'; then
    log_ok "AWS CLI supports --http-tokens-enforced"
  else
    log_warn "AWS CLI ($(aws --version 2>&1)) lacks --http-tokens-enforced; enforcement step will be skipped. Update the CLI on the build image."
  fi
}

log_section "Pre-API helpers"
report_current_defaults
case "$(customization_action)" in
  apply|destroy) check_cli_supports_enforced ;;
esac
