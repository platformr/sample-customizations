#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# post-api-helpers.sh -- runs AFTER `terraform <action>` for this customization.
#
# Typical uses:
#   * Finish configuration Terraform cannot express (API-only settings).
#   * VALIDATE that the customization is actually in effect and echo status.
#
# Rules:
#   * Must be idempotent: it runs on every apply and destroy, and the same
#     customization is applied to the same account repeatedly.
#   * Platformr does NOT run this script on a diff (plan). Only Terraform runs
#     then, so there is no "diff" branch below.
#   * Validation echoes [ OK ] / [FAIL] lines but does not exit non-zero on a
#     failed validation; the build should still complete.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

# ---- Validation functions ----------------------------------------------------
# One function per thing you want to prove. Each prints OK/FAIL and returns
# 0/1. Keep them side-effect free so apply and destroy can both call them.

validate_example() {
  # Replace with a real check, e.g.:
  #   local value
  #   value="$(aws ssm get-parameter --name "/platformr/.../deployed" \
  #              --query Parameter.Value --output text 2>/dev/null || true)"
  #   check_equals "SSM marker parameter" "$value" "true"
  log_warn "validate_example() is a placeholder; replace it with a real check."
  return 0
}

# Optional: run a python helper (see python/README.md).
#   run_python validate_something.py --region "$(aws_region)"

# ---- Main --------------------------------------------------------------------

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    log_info "Validating deployed configuration..."
    validate_example || true
    ;;
  destroy)
    log_info "Confirming teardown..."
    # e.g. check the resource is gone; invert the apply checks.
    ;;
esac
