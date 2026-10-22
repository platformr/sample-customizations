#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-bedrock-model-enablement / post-api-helpers.sh
#
# apply      : set the account data retention mode if requested (Fable 5.x
#              needs aws_review), then validate model access.
# apply      : for every model in /platformr/<name>/model_ids, call
#              GetFoundationModelAvailability and report agreement,
#              authorization, entitlement and region availability.
# destroy    : report that agreements are gone (NOT_AVAILABLE).
#
# Requires AWS CLI >= 2.27.42; older CLIs log a warning and skip.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-bedrock-model-enablement}"
SSM_PREFIX="/platformr/${CUSTOMIZATION_NAME}"
DEFAULT_MODEL_IDS="anthropic.claude-fable-5-1,anthropic.claude-opus-5-5"

cli_supports_model_access() {
  aws bedrock get-foundation-model-availability help >/dev/null 2>&1
}

model_ids() {
  local v
  v="$(aws ssm get-parameter --name "${SSM_PREFIX}/model_ids" --query Parameter.Value --output text 2>/dev/null || true)"
  if [[ -z "$v" || "$v" == "None" ]]; then v="${MODEL_IDS:-$DEFAULT_MODEL_IDS}"; fi
  printf '%s' "$v" | tr ',' ' '
}

availability_field() {
  aws bedrock get-foundation-model-availability --model-id "$1" --query "$2" --output text 2>/dev/null || true
}

validate_model() {
  local model="$1" agreement auth entitlement region_avail err rc=0
  agreement="$(availability_field "$model" agreementAvailability.status)"
  auth="$(availability_field "$model" authorizationStatus)"
  entitlement="$(availability_field "$model" entitlementAvailability)"
  region_avail="$(availability_field "$model" regionAvailability)"

  log_info "Model ${model}:"
  case "$agreement" in
    AVAILABLE) log_ok "  agreementAvailability: AVAILABLE" ;;
    PENDING)   log_warn "  agreementAvailability: PENDING (AWS emails when the agreement completes)" ;;
    ERROR)
      err="$(availability_field "$model" agreementAvailability.errorMessage)"
      log_fail "  agreementAvailability: ERROR (${err})"; rc=1 ;;
    *)         log_fail "  agreementAvailability: ${agreement:-<unknown>}"; rc=1 ;;
  esac
  check_equals "  authorizationStatus"    "$auth"         "AUTHORIZED" || rc=1
  check_equals "  entitlementAvailability" "$entitlement"  "AVAILABLE"  || rc=1
  check_equals "  regionAvailability"      "$region_avail" "AVAILABLE"  || rc=1
  return $rc
}

# ---- Data retention (Claude Fable 5.x requires aws_review) -------------------

cli_supports_data_retention() {
  aws bedrock get-account-data-retention help >/dev/null 2>&1
}

desired_retention_mode() {
  local v
  v="$(aws ssm get-parameter --name "${SSM_PREFIX}/data_retention_mode" --query Parameter.Value --output text 2>/dev/null || true)"
  if [[ -z "$v" || "$v" == "None" ]]; then v="${DATA_RETENTION_MODE:-unset}"; fi
  printf '%s' "$v"
}

current_retention_mode() {
  aws bedrock get-account-data-retention --query mode --output text 2>/dev/null || true
}

set_data_retention() {
  local desired current
  desired="$(desired_retention_mode)"
  if [[ "$desired" == "unset" ]]; then
    log_info "data_retention_mode is null; leaving the account's retention setting untouched."
    return 0
  fi
  if ! cli_supports_data_retention; then
    log_warn "AWS CLI lacks 'bedrock get/put-account-data-retention'; cannot set mode '${desired}'."
    log_warn "Set it manually: PUT https://bedrock.$(aws_region).amazonaws.com/data-retention {\"mode\":\"${desired}\"}"
    return 0
  fi
  current="$(current_retention_mode)"
  if [[ "$current" == "$desired" ]]; then
    log_info "Data retention mode already '${desired}' in $(aws_region)."
    return 0
  fi
  log_info "Setting data retention mode '${current:-inherit}' -> '${desired}' in $(aws_region)..."
  if aws bedrock put-account-data-retention --mode "$desired" >/dev/null; then
    log_ok "put-account-data-retention --mode ${desired}"
  else
    log_fail "put-account-data-retention failed (see error above)"
  fi
}

validate_data_retention() {
  local desired
  desired="$(desired_retention_mode)"
  [[ "$desired" == "unset" ]] && return 0
  if ! cli_supports_data_retention; then
    log_warn "Cannot verify data retention mode (CLI too old)."
    return 0
  fi
  check_equals "Data retention mode ($(aws_region))" "$(current_retention_mode)" "$desired"
}

validate_all() {
  local m
  for m in $(model_ids); do validate_model "$m" || true; done
}

validate_removed() {
  local m agreement
  for m in $(model_ids); do
    agreement="$(availability_field "$m" agreementAvailability.status)"
    if [[ "$agreement" == "AVAILABLE" ]]; then
      log_fail "Model ${m}: agreement still AVAILABLE"
    else
      log_ok "Model ${m}: agreement ${agreement:-removed}"
    fi
  done
  log_info "Note: invoking a model re-creates its agreement automatically; use IAM/SCP deny on bedrock:InvokeModel to block it."
}

log_section "Post-API helpers"
if ! cli_supports_model_access; then
  log_warn "AWS CLI lacks 'bedrock get-foundation-model-availability'; skipping validation. Update the CLI (>= 2.27.42) on the build image."
  exit 0
fi
case "$(customization_action)" in
  apply)
    set_data_retention
    log_info "Validating Bedrock model access..."
    validate_all
    validate_data_retention || true
    ;;
  destroy)
    validate_removed
    log_info "Data retention mode is left as-is on destroy (change it deliberately, not as a side effect)."
    ;;
esac
