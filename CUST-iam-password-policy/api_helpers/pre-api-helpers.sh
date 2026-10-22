#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-iam-password-policy / pre-api-helpers.sh
#
# Context only: prints the password policy currently in force so the build log
# shows before/after. No mutations.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

report_current_policy() {
  local out
  if out="$(aws iam get-account-password-policy --output text 2>/dev/null)"; then
    log_info "Current account password policy:"
    printf '%s\n' "$out" | sed 's/^/         /'
  else
    log_info "No custom password policy set; account is on the AWS default policy."
  fi
}

log_section "Pre-API helpers"
report_current_policy
