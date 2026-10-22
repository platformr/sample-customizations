#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# CUST-devops-agent / post-api-helpers.sh
#
# apply   : associate this AWS account with the agent space (accountType
#           "monitor"), enable the operator app (IAM auth flow), validate.
# destroy : confirm the agent space and SSM hand-off parameters are gone.
#
# Inputs come from SSM parameters written by Terraform:
#   /platformr/CUST-devops-agent/agent_space_id
#   /platformr/CUST-devops-agent/agent_space_role_arn
#   /platformr/CUST-devops-agent/operator_app_role_arn
#
# Validation prints [ OK ] / [FAIL] but never fails the build.
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

CUSTOMIZATION_NAME="${CUSTOMIZATION_NAME:-CUST-devops-agent}"
SSM_PREFIX="/platformr/${CUSTOMIZATION_NAME}"

# ---- Helpers -----------------------------------------------------------------

ssm_get() {
  aws ssm get-parameter --name "${SSM_PREFIX}/$1" --query Parameter.Value --output text 2>/dev/null || true
}

cli_supports_devops_agent() {
  aws devops-agent help >/dev/null 2>&1
}

load_handoff() {
  AGENT_SPACE_ID="$(ssm_get agent_space_id)"
  AGENT_SPACE_ROLE_ARN="$(ssm_get agent_space_role_arn)"
  OPERATOR_APP_ROLE_ARN="$(ssm_get operator_app_role_arn)"
  check_nonempty "SSM ${SSM_PREFIX}/agent_space_id" "$AGENT_SPACE_ID" || return 1
  check_nonempty "SSM ${SSM_PREFIX}/agent_space_role_arn" "$AGENT_SPACE_ROLE_ARN" || return 1
  check_nonempty "SSM ${SSM_PREFIX}/operator_app_role_arn" "$OPERATOR_APP_ROLE_ARN" || return 1
}

# Status of the "aws" service association for this account, or empty.
aws_association_status() {
  aws devops-agent list-associations \
    --agent-space-id "$AGENT_SPACE_ID" \
    --query "associations[?serviceId=='aws'].status | [0]" \
    --output text 2>/dev/null || true
}

operator_app_url() {
  aws devops-agent get-operator-app \
    --agent-space-id "$AGENT_SPACE_ID" \
    --query operatorAppUrl --output text 2>/dev/null || true
}

# ---- Configuration (apply only) ---------------------------------------------

associate_account() {
  local status account_id
  status="$(aws_association_status)"
  if [[ -n "$status" && "$status" != "None" ]]; then
    log_info "AWS account already associated (status: ${status}); skipping associate-service."
    return 0
  fi
  account_id="$(aws_account_id)"
  log_info "Associating account ${account_id} with agent space ${AGENT_SPACE_ID} as 'monitor'..."
  if aws devops-agent associate-service \
       --agent-space-id "$AGENT_SPACE_ID" \
       --service-id aws \
       --configuration "{\"aws\":{\"assumableRoleArn\":\"${AGENT_SPACE_ROLE_ARN}\",\"accountId\":\"${account_id}\",\"accountType\":\"monitor\"}}" \
       >/dev/null; then
    log_ok "associate-service (aws, monitor)"
  else
    log_fail "associate-service failed (see error above)"
  fi
}

enable_operator_app() {
  local url
  url="$(operator_app_url)"
  if [[ -n "$url" && "$url" != "None" ]]; then
    log_info "Operator app already enabled: ${url}"
    return 0
  fi
  log_info "Enabling operator app (IAM auth flow)..."
  if aws devops-agent enable-operator-app \
       --agent-space-id "$AGENT_SPACE_ID" \
       --auth-flow iam \
       --operator-app-role-arn "$OPERATOR_APP_ROLE_ARN" \
       >/dev/null; then
    log_ok "enable-operator-app (iam)"
  else
    log_fail "enable-operator-app failed (see error above)"
  fi
}

# ---- Validation ---------------------------------------------------------------

validate_agent_space() {
  local name
  name="$(aws devops-agent get-agent-space --agent-space-id "$AGENT_SPACE_ID" \
            --query agentSpace.name --output text 2>/dev/null || true)"
  check_nonempty "Agent space ${AGENT_SPACE_ID}" "$name"
}

validate_association() {
  local status
  # Ask the service to re-validate the role trust; returns nothing on success.
  aws devops-agent validate-aws-associations --agent-space-id "$AGENT_SPACE_ID" >/dev/null 2>&1 || true
  status="$(aws_association_status)"
  check_nonempty "AWS account association status" "$status"
}

validate_operator_app() {
  local url
  url="$(operator_app_url)"
  check_nonempty "Operator app URL" "$url"
}

validate_removed() {
  local id
  id="$(ssm_get agent_space_id)"
  if [[ -z "$id" || "$id" == "None" ]]; then
    log_ok "SSM hand-off parameters removed"
  else
    log_fail "SSM parameter ${SSM_PREFIX}/agent_space_id still present (${id})"
    if cli_supports_devops_agent; then
      local name
      name="$(aws devops-agent get-agent-space --agent-space-id "$id" --query agentSpace.name --output text 2>/dev/null || true)"
      if [[ -z "$name" || "$name" == "None" ]]; then
        log_ok "Agent space ${id} no longer exists"
      else
        log_fail "Agent space ${id} (${name}) still exists"
      fi
    fi
  fi
}

# ---- Main --------------------------------------------------------------------

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)
    load_handoff || die "Terraform hand-off parameters missing; did terraform apply succeed?"
    if ! cli_supports_devops_agent; then
      log_warn "'aws devops-agent' not available on this CLI; skipping association and operator app enablement."
      log_warn "Update the AWS CLI on the build image and re-run apply."
      exit 0
    fi
    associate_account
    enable_operator_app

    log_info "Validating..."
    validate_agent_space  || true
    validate_association  || true
    validate_operator_app || true
    ;;
  destroy)
    validate_removed || true
    ;;
esac
