#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-ec2-ebs-encryption-by-default / pre-api-helpers.sh
#
# Context only: shows the current setting and default key for the region.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

report_current_state() {
  local enabled key
  enabled="$(aws ec2 get-ebs-encryption-by-default --query EbsEncryptionByDefault --output text 2>/dev/null || true)"
  key="$(aws ec2 get-ebs-default-kms-key-id --query KmsKeyId --output text 2>/dev/null || true)"
  log_info "EBS encryption by default in $(aws_region): ${enabled:-<unknown>} (default key: ${key:-<unknown>})"
}

log_section "Pre-API helpers"
report_current_state
