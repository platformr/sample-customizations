#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-cost-anomaly-detection / pre-api-helpers.sh
#
# Pre-checks (no mutations):
#   * warn if a SERVICE-dimension monitor already exists with a different name
#     (AWS allows only one per account; apply would fail)
#   * list current monitors/subscriptions for context
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-cost-anomaly-detection}"
EXPECTED_MONITOR_NAME="${MONITOR_NAME:-$(aws ssm get-parameter --name "/platformr/${CUSTOMIZATION_NAME}/monitor_name" --query Parameter.Value --output text 2>/dev/null || echo platformr-aws-services-monitor)}"

check_existing_service_monitor() {
  local names
  names="$(aws ce get-anomaly-monitors \
            --query "AnomalyMonitors[?MonitorType=='DIMENSIONAL' && MonitorDimension=='SERVICE'].MonitorName" \
            --output text 2>/dev/null || true)"
  if [[ -z "$names" || "$names" == "None" ]]; then
    log_info "No SERVICE-dimension anomaly monitor exists yet."
    return 0
  fi
  local n
  for n in $names; do
    if [[ "$n" == "$EXPECTED_MONITOR_NAME" ]]; then
      log_info "Monitor '${n}' already exists (managed by this customization)."
    else
      log_warn "A SERVICE-dimension monitor named '${n}' already exists. AWS allows one per account; terraform apply will fail unless it is imported or removed."
    fi
  done
}

log_section "Pre-API helpers"
case "$(customization_action)" in
  apply) check_existing_service_monitor ;;
  destroy)    log_info "Nothing to prepare before destroy." ;;
esac
