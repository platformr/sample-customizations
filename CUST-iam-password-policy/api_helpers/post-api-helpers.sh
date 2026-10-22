#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-iam-password-policy / post-api-helpers.sh
#
# apply      : validate the live policy against the CIS values
# destroy    : confirm the custom policy is gone (account back on AWS default)
#
# Expected values default to the CIS / Config-rule values. Override with the
# EXPECT_* environment variables if variables.tf was changed.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

EXPECT_MIN_LENGTH="${EXPECT_MIN_LENGTH:-14}"
EXPECT_REUSE_PREVENTION="${EXPECT_REUSE_PREVENTION:-24}"
EXPECT_MAX_AGE="${EXPECT_MAX_AGE:-90}"

# policy_field <JMESPath under PasswordPolicy> -> value or empty
policy_field() {
  aws iam get-account-password-policy --query "PasswordPolicy.$1" --output text 2>/dev/null || true
}

validate_password_policy() {
  if ! aws iam get-account-password-policy >/dev/null 2>&1; then
    log_fail "No custom password policy exists (AWS default policy in force)"
    return 1
  fi
  local rc=0
  check_equals "MinimumPasswordLength"      "$(policy_field MinimumPasswordLength)"      "$EXPECT_MIN_LENGTH"       || rc=1
  check_equals "PasswordReusePrevention"    "$(policy_field PasswordReusePrevention)"    "$EXPECT_REUSE_PREVENTION" || rc=1
  check_equals "MaxPasswordAge"             "$(policy_field MaxPasswordAge)"             "$EXPECT_MAX_AGE"          || rc=1
  check_equals "RequireUppercaseCharacters" "$(policy_field RequireUppercaseCharacters)" "True"                     || rc=1
  check_equals "RequireLowercaseCharacters" "$(policy_field RequireLowercaseCharacters)" "True"                     || rc=1
  check_equals "RequireNumbers"             "$(policy_field RequireNumbers)"             "True"                     || rc=1
  check_equals "RequireSymbols"             "$(policy_field RequireSymbols)"             "True"                     || rc=1
  check_equals "AllowUsersToChangePassword" "$(policy_field AllowUsersToChangePassword)" "True"                     || rc=1
  # ExpirePasswords is derived by AWS from MaxPasswordAge > 0.
  check_equals "ExpirePasswords"            "$(policy_field ExpirePasswords)"            "True"                     || rc=1
  return $rc
}

validate_policy_removed() {
  if aws iam get-account-password-policy >/dev/null 2>&1; then
    log_fail "Custom password policy still exists"
    return 1
  fi
  log_ok "Custom password policy removed; AWS default policy in force"
}

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    log_info "Validating IAM password policy against CIS values..."
    validate_password_policy || true
    ;;
  destroy)
    validate_policy_removed || true
    ;;
esac
