#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-transaction-search / pre-api-helpers.sh
#
# Runs before Terraform. Nothing here mutates the account; it records the
# current Transaction Search state so the build log shows before/after.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

report_current_state() {
  local dest status
  dest="$(aws xray get-trace-segment-destination --query Destination --output text 2>/dev/null || true)"
  status="$(aws xray get-trace-segment-destination --query Status --output text 2>/dev/null || true)"
  log_info "Current trace segment destination: ${dest:-<unknown>} (${status:-<unknown>})"
  if [[ "$dest" == "CloudWatchLogs" ]]; then
    log_info "Transaction Search is already enabled in this region; apply will be a no-op for the destination."
  else
    log_info "Transaction Search is not enabled yet."
  fi
}

log_section "Pre-API helpers"
case "$(customization_action)" in
  apply)   report_current_state ;;
  destroy)
    report_current_state
    log_info "Terraform cannot revert the trace destination; post-api-helpers.sh will set it back to XRay."
    ;;
esac
