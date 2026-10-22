#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# new-customization.sh -- scaffold a new CUST-<suffix> directory from _TEMPLATE.
#
# Usage:
#   scripts/new-customization.sh <suffix> ["one-line description"]
#
# Example:
#   scripts/new-customization.sh guardduty-enable "Enable GuardDuty in the account"
#   -> creates CUST-guardduty-enable/
# ------------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUFFIX="${1:-}"
DESCRIPTION="${2:-One-line summary of what this customization does to the target account.}"

if [[ -z "$SUFFIX" ]]; then
  echo "usage: $0 <suffix> [description]" >&2
  exit 2
fi
SUFFIX="${SUFFIX#CUST-}"
if [[ ! "$SUFFIX" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
  echo "error: suffix must be letters, digits and dashes (got '$SUFFIX')" >&2
  exit 2
fi

NAME="CUST-${SUFFIX}"
DEST="${REPO_ROOT}/${NAME}"
if [[ -e "$DEST" ]]; then
  echo "error: ${DEST} already exists" >&2
  exit 1
fi

cp -R "${REPO_ROOT}/_TEMPLATE" "$DEST"
rm -rf "${DEST}/terraform/.terraform" "${DEST}/terraform/.terraform.lock.hcl" "${DEST}/api_helpers/python/.venv"

# Replace placeholders (portable: no sed -i differences between GNU/BSD).
while IFS= read -r -d '' f; do
  sed -e "s/CUST-CHANGE-ME/${NAME}/g" \
      -e "s|^> One-line summary.*|> ${DESCRIPTION}|" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done < <(find "$DEST" -type f \( -name '*.tf' -o -name '*.md' -o -name '*.sh' \) -print0)

chmod +x "${DEST}"/api_helpers/*.sh

cat <<MSG
Created ${NAME}/

Next steps:
  1. Edit ${NAME}/terraform/main.tf (resources) and variables.tf
  2. Edit ${NAME}/api_helpers/pre-api-helpers.sh and post-api-helpers.sh
     (add real validate_* functions to the post helper)
  3. Fill in ${NAME}/README.md
  4. Run: scripts/validate-customization.sh ${NAME}
MSG
