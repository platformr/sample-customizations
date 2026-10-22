#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# validate-customization.sh -- static checks for one or more customizations.
#
# Usage:
#   scripts/validate-customization.sh                 # all CUST-* dirs + _TEMPLATE
#   scripts/validate-customization.sh CUST-foo [...]  # specific directories
#
# Environment:
#   TF_CLI=<binary>  Terraform-compatible CLI to use: "terraform" or "tofu"
#                    (OpenTofu). Default: terraform if installed, else tofu.
#   SKIP_TF_INIT=1   skip `init` (use when providers are already cached and
#                    you are offline). `validate` still runs.
#
# Checks performed per customization:
#   1. Directory layout and naming convention
#   2. Shell scripts: bash -n, shellcheck (if installed)
#   3. Python scripts: py_compile
#   4. fmt -check, init -backend=false, validate (terraform or tofu, see TF_CLI)
#   5. tflint (if installed; warnings only)
#   6. Anti-pattern grep: backend blocks, remote state, cross-CUST references,
#      hard-coded account IDs (warning)
#   7. (whole-repo runs only) skills/*/SKILL.md frontmatter and agent symlinks
#
# Exit code is non-zero if any check FAILS. Warnings do not fail the run.
# ------------------------------------------------------------------------------
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FAILURES=0
WARNINGS=0

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

fail() { red   "  [FAIL] $*"; FAILURES=$((FAILURES + 1)); }
warn() { yellow "  [WARN] $*"; WARNINGS=$((WARNINGS + 1)); }
ok()   { green "  [ OK ] $*"; }

# Terraform-compatible CLI: terraform (HashiCorp) or tofu (OpenTofu). Both read
# the TF_* environment variables and share the same subcommands.
if [[ -z "${TF_CLI:-}" ]]; then
  if command -v terraform >/dev/null 2>&1; then TF_CLI=terraform
  elif command -v tofu >/dev/null 2>&1; then TF_CLI=tofu
  else TF_CLI=terraform; fi
fi
export TF_CLI

# Share provider downloads between customizations.
if [[ -z "${TF_PLUGIN_CACHE_DIR:-}" ]]; then
  export TF_PLUGIN_CACHE_DIR="${TMPDIR:-/tmp}/platformr-tf-plugin-cache"
fi
mkdir -p "$TF_PLUGIN_CACHE_DIR"
export TF_IN_AUTOMATION=1

check_layout() {
  local dir="$1" name
  name="$(basename "$dir")"

  if [[ "$name" != "_TEMPLATE" && ! "$name" =~ ^CUST-[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
    fail "Directory name '$name' must match CUST-<suffix> (letters, digits, dashes)"
  else
    ok "Directory name"
  fi

  local f
  for f in api_helpers/pre-api-helpers.sh api_helpers/post-api-helpers.sh \
           api_helpers/python/requirements.txt README.md; do
    if [[ -f "$dir/$f" ]]; then ok "exists: $f"; else fail "missing: $f"; fi
  done
  for f in api_helpers/pre-api-helpers.sh api_helpers/post-api-helpers.sh; do
    [[ -x "$dir/$f" ]] || fail "not executable: $f (chmod +x)"
  done
  if compgen -G "$dir/terraform/*.tf" >/dev/null; then
    ok "terraform/ has .tf files"
  else
    fail "terraform/ has no .tf files"
  fi
  if [[ "$name" != "_TEMPLATE" ]] && grep -q "CUST-CHANGE-ME" -r "$dir" 2>/dev/null; then
    fail "placeholder 'CUST-CHANGE-ME' still present (grep -rn CUST-CHANGE-ME $dir)"
  fi
}

check_shell() {
  local dir="$1" f
  while IFS= read -r -d '' f; do
    if bash -n "$f" 2>/dev/null; then ok "bash -n ${f#"$dir"/}"; else fail "bash -n ${f#"$dir"/}"; fi
    if command -v shellcheck >/dev/null 2>&1; then
      if shellcheck -x -S warning "$f"; then ok "shellcheck ${f#"$dir"/}"; else fail "shellcheck ${f#"$dir"/}"; fi
    fi
  done < <(find "$dir" -type f -name '*.sh' -not -path '*/.venv/*' -print0)
  command -v shellcheck >/dev/null 2>&1 || warn "shellcheck not installed; skipped (brew install shellcheck)"
}

check_python() {
  local dir="$1" f
  while IFS= read -r -d '' f; do
    if python3 -I -m py_compile "$f" 2>/dev/null; then ok "py_compile ${f#"$dir"/}"; else fail "py_compile ${f#"$dir"/}"; fi
  done < <(find "$dir" -type f -name '*.py' -not -path '*/.venv/*' -print0)
  find "$dir" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null
}

check_terraform() {
  local dir="$1" tfdir="$1/terraform"
  if ! command -v "$TF_CLI" >/dev/null 2>&1; then
    fail "$TF_CLI not installed (set TF_CLI=terraform or TF_CLI=tofu)"
    return
  fi

  if "$TF_CLI" -chdir="$tfdir" fmt -check -recursive -diff >/dev/null 2>&1; then
    ok "$TF_CLI fmt"
  else
    fail "$TF_CLI fmt (run: $TF_CLI -chdir=$tfdir fmt -recursive)"
    "$TF_CLI" -chdir="$tfdir" fmt -check -recursive -diff 2>&1 | sed 's/^/         /'
  fi

  if [[ "${SKIP_TF_INIT:-0}" != "1" ]]; then
    if "$TF_CLI" -chdir="$tfdir" init -backend=false -input=false -no-color >/dev/null 2>"$tfdir/.init.err"; then
      ok "$TF_CLI init"
    else
      fail "$TF_CLI init"; sed 's/^/         /' "$tfdir/.init.err"
    fi
    rm -f "$tfdir/.init.err"
  fi

  if "$TF_CLI" -chdir="$tfdir" validate -no-color >"$tfdir/.validate.out" 2>&1; then
    ok "$TF_CLI validate"
  else
    fail "$TF_CLI validate"; sed 's/^/         /' "$tfdir/.validate.out"
  fi
  rm -f "$tfdir/.validate.out"

  if command -v tflint >/dev/null 2>&1; then
    if tflint --chdir="$tfdir" --no-color >/dev/null 2>&1; then
      ok "tflint"
    else
      warn "tflint reported issues (tflint --chdir=$tfdir)"
    fi
  fi
}

check_antipatterns() {
  local dir="$1" tfdir="$1/terraform"
  if grep -En '^\s*backend\s+"' "$tfdir"/*.tf >/dev/null 2>&1; then
    fail "backend block found in terraform/: Platformr injects the backend"
  else
    ok "no backend block"
  fi
  if grep -En 'terraform_remote_state' "$tfdir"/*.tf >/dev/null 2>&1; then
    fail "terraform_remote_state found: customizations must not depend on each other"
  else
    ok "no remote state reads"
  fi
  if grep -REn '\.\./CUST-|/CUST-[A-Za-z0-9-]+/' "$dir" --include='*.sh' --include='*.tf' --include='*.py' 2>/dev/null | grep -v "$(basename "$dir")" >/dev/null; then
    fail "reference to another CUST- directory found: no cross-customization dependencies"
  else
    ok "no cross-customization references"
  fi
  if grep -REn '\b[0-9]{12}\b' "$tfdir" --include='*.tf' --exclude-dir='.terraform' 2>/dev/null | grep -v '^\s*#' >/dev/null; then
    warn "possible hard-coded AWS account ID in terraform/ (use data.aws_caller_identity)"
  fi
}

validate_one() {
  local dir="$1"
  printf '\n%s\n' "=== $(basename "$dir") ==="
  check_layout "$dir"
  check_shell "$dir"
  check_python "$dir"
  check_terraform "$dir"
  check_antipatterns "$dir"
}

check_skills() {
  printf '\n%s\n' "=== skills ==="
  local d name desc dname
  for d in skills/*/; do
    [[ -f "$d/SKILL.md" ]] || continue
    dname="$(basename "$d")"
    name="$(sed -n '/^---$/,/^---$/p' "$d/SKILL.md" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
    desc="$(sed -n '/^---$/,/^---$/p' "$d/SKILL.md" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
    if [[ "$name" == "$dname" ]]; then ok "skills/$dname: name matches folder"; else fail "skills/$dname: frontmatter name '$name' != folder"; fi
    if [[ -n "$desc" ]]; then ok "skills/$dname: has description"; else fail "skills/$dname: missing description"; fi
  done
  local link
  for link in .claude/skills .agents/skills .kiro/skills; do
    if [[ -L "$link" && -d "$link" ]]; then ok "$link -> $(readlink "$link")"
    elif [[ -d "$link" ]]; then warn "$link is a real directory, not a link to skills/ (scripts/link-skills.sh --force)"
    else fail "$link missing (run scripts/link-skills.sh)"; fi
  done
}

printf 'Using %s (%s)\n' "$TF_CLI" "$("$TF_CLI" version 2>/dev/null | head -1 || echo 'not found')"

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  while IFS= read -r d; do TARGETS+=("$d"); done < <(find . -maxdepth 1 -type d \( -name 'CUST-*' -o -name '_TEMPLATE' \) | sort)
fi

for t in "${TARGETS[@]}"; do
  t="${t%/}"
  if [[ ! -d "$t" ]]; then fail "not a directory: $t"; continue; fi
  validate_one "$t"
done

# Skills are checked whenever the whole repo is validated (no explicit targets).
if [[ $# -eq 0 ]]; then check_skills; fi

printf '\n'
if [[ $FAILURES -gt 0 ]]; then
  red "Validation FAILED: $FAILURES failure(s), $WARNINGS warning(s)"
  exit 1
fi
green "Validation passed: 0 failures, $WARNINGS warning(s)"
