#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-cost-anomaly-detection / post-api-helpers.sh
#
# apply      : validate the monitor and the email subscription exist and the
#              subscriber address matches
# destroy    : confirm both are gone
#
# Names come from SSM parameters written by Terraform.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-cost-anomaly-detection}"
SSM_PREFIX="/platformr/${CUSTOMIZATION_NAME}"

ssm_get() {
  aws ssm get-parameter --name "${SSM_PREFIX}/$1" --query Parameter.Value --output text 2>/dev/null || true
}

MONITOR_NAME="${MONITOR_NAME:-$(ssm_get monitor_name)}"
SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-$(ssm_get subscription_name)}"
ALERT_EMAIL="${ALERT_EMAIL:-$(ssm_get alert_email)}"
MONITOR_NAME="${MONITOR_NAME:-platformr-aws-services-monitor}"
SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-platformr-cost-anomaly-alerts}"

monitor_arn() {
  aws ce get-anomaly-monitors \
    --query "AnomalyMonitors[?MonitorName=='${MONITOR_NAME}'].MonitorArn | [0]" \
    --output text 2>/dev/null || true
}

validate_monitor() {
  check_nonempty "Anomaly monitor '${MONITOR_NAME}'" "$(monitor_arn)"
}

validate_subscription() {
  local arn email freq
  arn="$(aws ce get-anomaly-subscriptions \
          --query "AnomalySubscriptions[?SubscriptionName=='${SUBSCRIPTION_NAME}'].SubscriptionArn | [0]" \
          --output text 2>/dev/null || true)"
  check_nonempty "Anomaly subscription '${SUBSCRIPTION_NAME}'" "$arn" || return 1
  email="$(aws ce get-anomaly-subscriptions \
            --query "AnomalySubscriptions[?SubscriptionName=='${SUBSCRIPTION_NAME}'].Subscribers[?Type=='EMAIL'].Address | [0][0]" \
            --output text 2>/dev/null || true)"
  freq="$(aws ce get-anomaly-subscriptions \
            --query "AnomalySubscriptions[?SubscriptionName=='${SUBSCRIPTION_NAME}'].Frequency | [0]" \
            --output text 2>/dev/null || true)"
  if [[ -n "$ALERT_EMAIL" && "$ALERT_EMAIL" != "None" ]]; then
    check_equals "Subscriber email" "$email" "$ALERT_EMAIL"
  else
    check_nonempty "Subscriber email" "$email"
  fi
  check_nonempty "Alert frequency" "$freq"
  if [[ "$email" == *"@example.com" ]]; then
    log_warn "Alert email still points at example.com; set var.alert_email to a real mailbox."
  fi
}

validate_removed() {
  local arn
  arn="$(monitor_arn)"
  if [[ -z "$arn" || "$arn" == "None" ]]; then
    log_ok "Anomaly monitor '${MONITOR_NAME}' removed"
  else
    log_fail "Anomaly monitor '${MONITOR_NAME}' still exists (${arn})"
  fi
}

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    log_info "Validating Cost Anomaly Detection..."
    validate_monitor      || true
    validate_subscription || true
    ;;
  destroy)
    validate_removed || true
    ;;
esac
