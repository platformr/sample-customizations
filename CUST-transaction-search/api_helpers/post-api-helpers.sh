#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-transaction-search / post-api-helpers.sh
#
# apply   : validate Transaction Search is active (bash + python checks)
# destroy : revert the trace segment destination to XRay (Terraform's delete of
#           aws_xray_trace_segment_destination is a no-op), then validate.
#
# Validation prints [ OK ] / [FAIL] but never fails the build.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

# Set to "false" to leave Transaction Search enabled when this customization is
# destroyed (e.g. another process still relies on it).
REVERT_ON_DESTROY="${REVERT_TRANSACTION_SEARCH_ON_DESTROY:-true}"
POLICY_NAME="${TRANSACTION_SEARCH_POLICY_NAME:-TransactionSearchAccess}"

# ---- Validation functions ----------------------------------------------------

validate_trace_destination() {
  local dest status
  dest="$(aws xray get-trace-segment-destination --query Destination --output text 2>/dev/null || true)"
  status="$(aws xray get-trace-segment-destination --query Status --output text 2>/dev/null || true)"
  check_equals "Trace segment destination" "$dest" "CloudWatchLogs" || return 1
  if [[ "$status" == "ACTIVE" ]]; then
    log_ok "Trace segment destination status: ACTIVE"
  elif [[ "$status" == "PENDING" ]]; then
    log_warn "Trace segment destination status: PENDING (can take ~10 minutes to become ACTIVE)"
  else
    log_fail "Trace segment destination status: ${status:-<unknown>}"
    return 1
  fi
}

validate_indexing_rule() {
  local pct
  pct="$(aws xray get-indexing-rules \
          --query "IndexingRules[?Name=='Default'].Rule.Probabilistic.DesiredSamplingPercentage | [0]" \
          --output text 2>/dev/null || true)"
  check_nonempty "Default indexing rule sampling percentage" "$pct"
}

validate_logs_resource_policy() {
  local name
  name="$(aws logs describe-resource-policies \
           --query "resourcePolicies[?policyName=='${POLICY_NAME}'].policyName | [0]" \
           --output text 2>/dev/null || true)"
  check_equals "CloudWatch Logs resource policy" "$name" "$POLICY_NAME"
}

validate_reverted() {
  local dest
  dest="$(aws xray get-trace-segment-destination --query Destination --output text 2>/dev/null || true)"
  check_equals "Trace segment destination" "$dest" "XRay"
}

# ---- Actions -----------------------------------------------------------------

revert_trace_destination() {
  if [[ "$REVERT_ON_DESTROY" != "true" ]]; then
    log_warn "REVERT_TRANSACTION_SEARCH_ON_DESTROY=${REVERT_ON_DESTROY}; leaving Transaction Search enabled."
    return 0
  fi
  log_info "Reverting trace segment destination to XRay..."
  if aws xray update-trace-segment-destination --destination XRay >/dev/null; then
    log_ok "update-trace-segment-destination --destination XRay"
  else
    log_fail "update-trace-segment-destination failed (see error above)"
  fi
}

# ---- Main --------------------------------------------------------------------

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    log_info "Validating Transaction Search configuration (bash)..."
    validate_logs_resource_policy || true
    validate_trace_destination    || true
    validate_indexing_rule        || true

    log_info "Validating span ingestion details (python/boto3)..."
    run_python validate_transaction_search.py --region "$(aws_region)" --policy-name "$POLICY_NAME" || true
    ;;
  destroy)
    revert_trace_destination
    validate_reverted || true
    ;;
esac
