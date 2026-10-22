#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# pre-api-helpers.sh -- runs BEFORE `terraform <action>` for this customization.
#
# Typical uses:
#   * Print the AWS context so the build log is self-describing.
#   * Check pre-conditions (service availability, quotas, prerequisites).
#   * Perform setup that Terraform cannot (opt-in APIs, one-off enablements).
#
# Rules:
#   * Must be idempotent: it runs on every apply and destroy, and the same
#     customization is applied to the same account repeatedly.
#   * Platformr does NOT run this script on a diff (plan). Only Terraform runs
#     then, so there is no "diff" branch below.
#   * Report status with log_ok / log_warn / log_fail; only `die` on a genuine
#     blocker.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

log_section "Pre-API helpers"
case "$(customization_action)" in
  apply)
    log_info "Nothing to prepare before apply."
    ;;
  destroy)
    log_info "Nothing to prepare before destroy."
    ;;
esac
