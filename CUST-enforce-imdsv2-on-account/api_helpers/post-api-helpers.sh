#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-enforce-imdsv2-on-account / post-api-helpers.sh
#
# apply   : if /platformr/<name>/enforce == true, set HttpTokensEnforced=enabled
#           (not supported by the Terraform provider), then validate.
# destroy : set HttpTokensEnforced=disabled (Terraform's delete only resets
#           the defaults), then validate defaults are back to no-preference.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-enforce-imdsv2-on-account}"
SSM_PREFIX="/platformr/${CUSTOMIZATION_NAME}"

imds_field() {
  aws ec2 get-instance-metadata-defaults --query "$1" --output text 2>/dev/null || true
}

cli_supports_enforced() {
  aws ec2 modify-instance-metadata-defaults help 2>/dev/null | grep -q -- '--http-tokens-enforced'
}

want_enforce() {
  local v
  v="$(aws ssm get-parameter --name "${SSM_PREFIX}/enforce" --query Parameter.Value --output text 2>/dev/null || echo true)"
  [[ "$v" == "true" ]]
}

set_enforced() {
  local desired="$1" current
  current="$(imds_field AccountLevel.HttpTokensEnforced)"
  if [[ "$current" == "$desired" ]]; then
    log_info "HttpTokensEnforced already ${desired}; nothing to do."
    return 0
  fi
  if ! cli_supports_enforced; then
    log_warn "Cannot set HttpTokensEnforced=${desired}: AWS CLI lacks --http-tokens-enforced."
    return 0
  fi
  log_info "Setting HttpTokensEnforced=${desired} in $(aws_region)..."
  if aws ec2 modify-instance-metadata-defaults --http-tokens-enforced "$desired" >/dev/null; then
    log_ok "modify-instance-metadata-defaults --http-tokens-enforced ${desired}"
  else
    log_fail "modify-instance-metadata-defaults failed (see error above)"
  fi
}

validate_defaults() {
  local rc=0
  check_equals "AccountLevel.HttpTokens"   "$(imds_field AccountLevel.HttpTokens)"   "required" || rc=1
  check_equals "AccountLevel.HttpEndpoint" "$(imds_field AccountLevel.HttpEndpoint)" "enabled"  || rc=1
  check_nonempty "AccountLevel.HttpPutResponseHopLimit" "$(imds_field AccountLevel.HttpPutResponseHopLimit)" || rc=1
  if want_enforce; then
    check_equals "AccountLevel.HttpTokensEnforced" "$(imds_field AccountLevel.HttpTokensEnforced)" "enabled" || rc=1
  else
    log_info "Enforcement not requested (var.enforce=false); HttpTokensEnforced=$(imds_field AccountLevel.HttpTokensEnforced)"
  fi
  log_info "ManagedBy: $(imds_field ManagedBy)"
  return $rc
}

validate_reverted() {
  local tokens enforced
  tokens="$(imds_field AccountLevel.HttpTokens)"
  enforced="$(imds_field AccountLevel.HttpTokensEnforced)"
  if [[ -z "$tokens" || "$tokens" == "None" || "$tokens" == "no-preference" ]]; then
    log_ok "AccountLevel.HttpTokens reset (no preference)"
  else
    log_fail "AccountLevel.HttpTokens still '${tokens}'"
  fi
  if [[ -z "$enforced" || "$enforced" == "None" || "$enforced" == "disabled" ]]; then
    log_ok "AccountLevel.HttpTokensEnforced disabled"
  else
    log_fail "AccountLevel.HttpTokensEnforced still '${enforced}'"
  fi
}

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    if want_enforce; then set_enforced enabled; fi
    log_info "Validating IMDS account defaults..."
    validate_defaults || true
    ;;
  destroy)
    set_enforced disabled
    validate_reverted || true
    ;;
esac
