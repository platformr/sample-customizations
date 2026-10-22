---
name: write-api-helpers
description: Write or review pre-api-helpers.sh, post-api-helpers.sh and api_helpers/python scripts for a Platformr Customization, including validation functions that echo status. Use when adding helper scripts, post-deployment checks, API-only configuration steps, or boto3 scripts to a CUST-* directory.
---

# Writing api_helpers for a customization

Helpers wrap the Terraform run. Platformr executes, from inside
`CUST-<name>/api_helpers/`:

```
pre-api-helpers.sh   -> terraform <action> (in ../terraform) -> post-api-helpers.sh
```

Both scripts run on `apply` and `destroy` only. **A `diff` run executes
`terraform plan` and nothing else: Platformr does not invoke the helper
scripts on diff**, so never write a `diff` branch and never rely on a helper
for plan-time checks. The action is exposed as `PLATFORMR_ACTION`;
`lib/bash/common.sh` normalises it via `customization_action` (unset defaults
to `apply`).

## Skeleton (copy from `_TEMPLATE/api_helpers/`)

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

require_cmd aws
print_aws_context

validate_thing() {
  local v
  v="$(aws svc get-thing --query 'Thing.Status' --output text 2>/dev/null || true)"
  check_equals "Thing status" "$v" "ENABLED"
}

log_section "Post-API helpers"
case "$(customization_action)" in
  apply)   configure_thing; validate_thing || true ;;
  destroy) validate_thing_removed || true ;;
  # no diff branch: helpers are not run on diff
esac
```

## Rules

1. **Idempotent.** Check current state before changing it. Re-running apply
   on an already-configured account must be a no-op that still prints OK.
2. **No `diff` branch.** Helpers do not run on diff. Handle `apply` and
   `destroy` only; anything you need to know at plan time must come from
   Terraform itself.
3. **Validation reports, it does not abort.** `validate_*` functions print
   `[ OK ]` / `[FAIL]` via `check_equals` / `check_nonempty` and return 0/1.
   Call them with `|| true`. Only `die` on a true blocker (missing CLI,
   missing SSM parameter the helper cannot proceed without, wrong region).
4. **No `jq`.** Use `aws --query '<JMESPath>' --output text`. Treat the
   literal string `None` as empty.
5. **Get Terraform values via SSM, not state.** Terraform writes
   `aws_ssm_parameter` under `/platformr/<CUST-name>/...`; the helper reads
   `aws ssm get-parameter --name ... --query Parameter.Value --output text`.
6. **Context first.** Call `print_aws_context` so the build log shows
   account, region, caller and action.
7. **Region** comes from `aws_region` (AWS_REGION / AWS_DEFAULT_REGION /
   CLI config). Never hard-code it. Account ID from `aws_account_id`.
8. **Shared code goes in `lib/`.** Add functions to `lib/bash/common.sh`
   (or a new `lib/bash/<topic>.sh`) when two customizations would need them.
   Never source another `CUST-*` directory.
9. **Tolerate missing CLI features.** If a sub-command may not exist on older
   AWS CLI builds, probe with `aws <svc> help >/dev/null 2>&1` and
   `log_warn` + skip instead of failing.
10. **Destroy.** If Terraform's delete is a no-op for a resource (check the
    provider docs), revert it here on `destroy` and validate the reverted
    state. Say so in the README.

## Python helpers

Use `api_helpers/python/` when boto3 is clearer than CLI+JMESPath (pagination,
multi-step logic, structured comparison). Add deps to `requirements.txt`, then
from bash:

```bash
run_python validate_thing.py --region "$(aws_region)"
```

`run_python` builds a git-ignored venv, installs requirements, and runs the
script with `python -I`. Script conventions:

- `argparse` flags for inputs; `--region` at least.
- Print the same `[ OK ]` / `[FAIL]` / `[WARN]` prefixes as bash.
- `sys.exit(0)` unless it is a genuine blocker.
- Catch `botocore.exceptions.ClientError` and report, do not traceback.

## Library reference (`lib/bash/common.sh`)

| Function | Purpose |
| --- | --- |
| `log_info/log_ok/log_warn/log_fail/log_section` | Consistent prefixed output |
| `die msg` | Print and exit 1 (use sparingly) |
| `customization_action`, `is_apply`, `is_destroy` | Action detection (`apply` or `destroy`; `diff` is never expected) |
| `require_cmd a b` | Abort if a command is missing |
| `aws_region`, `aws_account_id`, `aws_partition` | Context lookups |
| `print_aws_context` | Log the context block |
| `check_equals label actual expected` | OK/FAIL comparison, returns 0/1 |
| `check_nonempty label value` | OK/FAIL presence check |
| `run_python script.py args` | Run a python helper in a venv |
