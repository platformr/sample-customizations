#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Shared helper library for Platformr Customization api_helpers scripts.
#
# Source this file from a pre-api-helpers.sh or post-api-helpers.sh:
#
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=../../lib/bash/common.sh
#   source "${SCRIPT_DIR}/../../lib/bash/common.sh"
#
# Everything here is intentionally dependency-light: bash, coreutils and the
# AWS CLI v2. `jq` is NOT required; use `aws --query` + `--output text` instead.
#
# Nothing in this library exits the process on a validation failure. Helpers
# are expected to REPORT status (ok / warn / fail) and let the build continue.
# Use `die` only for genuine, unrecoverable pre-conditions.
# ------------------------------------------------------------------------------

# Guard against double-sourcing.
if [[ -n "${_PLATFORMR_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
_PLATFORMR_COMMON_SH_LOADED=1

# ---- Logging -----------------------------------------------------------------

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok()   { printf '[ OK ] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_fail() { printf '[FAIL] %s\n' "$*" >&2; }
log_section() { printf '\n==== %s ====\n' "$*"; }

# die <message>  -- print and exit non-zero. Use sparingly (see header).
die() { log_fail "$*"; exit 1; }

# ---- Action detection --------------------------------------------------------

# The build environment runs exactly one customization per run with one action:
#   apply   -> pre helper, terraform apply, post helper
#   destroy -> pre helper, terraform destroy, post helper
#   diff    -> terraform plan ONLY. Platformr does NOT run the pre/post helper
#              scripts on a diff, so helpers never need a "diff" branch.
#
# The action is exported to the helper scripts as PLATFORMR_ACTION. If it is not
# set we assume "apply". If a helper is somehow invoked with diff/plan (e.g. by
# hand), customization_action still returns "diff" and warns; a case statement
# that only handles apply/destroy then does nothing, which is the safe outcome.
customization_action() {
  local action="${PLATFORMR_ACTION:-apply}"
  action="$(printf '%s' "$action" | tr '[:upper:]' '[:lower:]')"
  case "$action" in
    apply|destroy) printf '%s' "$action" ;;
    diff|plan)
      log_warn "PLATFORMR_ACTION='${action}': Platformr does not run helper scripts on diff; nothing will be done."
      printf 'diff'
      ;;
    *)
      log_warn "Unknown PLATFORMR_ACTION='${action}', treating as 'apply'"
      printf 'apply'
      ;;
  esac
}

is_apply()   { [[ "$(customization_action)" == "apply" ]]; }
is_destroy() { [[ "$(customization_action)" == "destroy" ]]; }

# ---- AWS context -------------------------------------------------------------

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
  done
}

aws_region() {
  local region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  if [[ -z "$region" ]]; then
    region="$(aws configure get region 2>/dev/null || true)"
  fi
  [[ -n "$region" ]] || die "Unable to determine AWS region (set AWS_REGION)"
  printf '%s' "$region"
}

aws_account_id() {
  aws sts get-caller-identity --query Account --output text
}

aws_partition() {
  aws sts get-caller-identity --query Arn --output text | cut -d: -f2
}

# print_aws_context -- echo who/where we are running. Call at the top of every
# helper so the build log is self-describing.
print_aws_context() {
  log_section "AWS context"
  log_info "Customization : ${CUSTOMIZATION_NAME:-$(basename "$(cd "${SCRIPT_DIR:-.}/.." && pwd)")}"
  log_info "Action        : $(customization_action)"
  log_info "Account       : $(aws_account_id)"
  log_info "Region        : $(aws_region)"
  log_info "Caller        : $(aws sts get-caller-identity --query Arn --output text)"
}

# ---- Validation helpers ------------------------------------------------------

# check_equals <label> <actual> <expected>
# Prints OK/FAIL and returns 0/1 WITHOUT exiting. Callers should ignore the
# return value unless they deliberately want to fail the build.
check_equals() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    log_ok "${label}: ${actual}"
    return 0
  fi
  log_fail "${label}: expected '${expected}', got '${actual:-<empty>}'"
  return 1
}

# check_nonempty <label> <value>
check_nonempty() {
  local label="$1" value="$2"
  if [[ -n "$value" && "$value" != "None" ]]; then
    log_ok "${label}: ${value}"
    return 0
  fi
  log_fail "${label}: not found"
  return 1
}

# ---- Python support ----------------------------------------------------------

# run_python <script.py> [args...]
#
# Runs a script from the customization's api_helpers/python directory inside a
# throw-away virtualenv (api_helpers/python/.venv) with requirements.txt
# installed. The venv is git-ignored. Requires python3 on the build image.
run_python() {
  local script="$1"; shift || true
  local py_dir
  py_dir="$(cd "${SCRIPT_DIR:-.}/python" && pwd)"
  local venv="${py_dir}/.venv"

  require_cmd python3

  if [[ ! -x "${venv}/bin/python" ]]; then
    log_info "Creating virtualenv at ${venv}"
    python3 -m venv "$venv"
  fi
  if [[ -s "${py_dir}/requirements.txt" ]]; then
    log_info "Installing python requirements"
    "${venv}/bin/pip" install --quiet --disable-pip-version-warning -r "${py_dir}/requirements.txt"
  fi
  # -I: isolated mode. Do not pick up stray modules from CWD.
  "${venv}/bin/python" -I "${py_dir}/${script}" "$@"
}
