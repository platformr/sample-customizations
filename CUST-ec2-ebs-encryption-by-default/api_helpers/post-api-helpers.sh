#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-ec2-ebs-encryption-by-default / post-api-helpers.sh
#
# apply      : validate encryption by default is enabled in this region and
#              report the default KMS key
# destroy    : validate it is disabled again
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

# Optional: set to the expected customer-managed key ARN/alias to assert it.
EXPECT_DEFAULT_KMS_KEY="${EXPECT_DEFAULT_KMS_KEY:-}"

ebs_encryption_enabled() {
  aws ec2 get-ebs-encryption-by-default --query EbsEncryptionByDefault --output text 2>/dev/null || true
}

validate_enabled() {
  check_equals "EBS encryption by default ($(aws_region))" "$(ebs_encryption_enabled)" "True"
}

validate_default_key() {
  local key
  key="$(aws ec2 get-ebs-default-kms-key-id --query KmsKeyId --output text 2>/dev/null || true)"
  if [[ -n "$EXPECT_DEFAULT_KMS_KEY" ]]; then
    check_equals "Default EBS KMS key" "$key" "$EXPECT_DEFAULT_KMS_KEY"
  else
    check_nonempty "Default EBS KMS key" "$key"
  fi
}

validate_disabled() {
  check_equals "EBS encryption by default ($(aws_region))" "$(ebs_encryption_enabled)" "False"
}

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    log_info "Validating EBS encryption by default..."
    validate_enabled     || true
    validate_default_key || true
    ;;
  destroy)
    validate_disabled || true
    ;;
esac
