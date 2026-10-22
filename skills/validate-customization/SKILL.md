---
name: validate-customization
description: Run and fix the static checks for Platformr Customizations (terraform fmt, terraform validate, shell/python syntax, layout and anti-pattern checks). Use after creating or editing any CUST-* directory, before committing, or when asked to lint, validate, check or format a customization.
---

# Validate a Platformr Customization

Always run this after editing anything under a `CUST-*` directory or
`_TEMPLATE/`. It is the same check a reviewer runs.

## Run

```bash
scripts/validate-customization.sh            # everything
scripts/validate-customization.sh CUST-foo   # one customization
```

Needs: `terraform` (>= 1.5), `python3`, network access for `terraform init`
(providers are cached in `TF_PLUGIN_CACHE_DIR`). Optional: `shellcheck`,
`tflint`. Set `SKIP_TF_INIT=1` to skip init when offline and already cached.

## What it checks and how to fix each failure

| Check | Fix |
| --- | --- |
| Directory name | Rename to `CUST-<letters-digits-dashes>`. |
| Missing files | Copy the missing file from `_TEMPLATE/` and fill it in. |
| Not executable | `chmod +x CUST-foo/api_helpers/*.sh` |
| `CUST-CHANGE-ME` present | Replace with the real directory name. |
| `bash -n` / shellcheck | Fix the reported line. Keep `set -euo pipefail`. |
| `py_compile` | Fix the Python syntax error. |
| `terraform fmt` | `terraform -chdir=CUST-foo/terraform fmt -recursive` |
| `terraform init` | Usually a bad `required_providers` block or no network. |
| `terraform validate` | Read the error; typically a wrong attribute name. Check the provider docs for the resource. |
| backend block | Delete it. Platformr injects the backend. |
| `terraform_remote_state` | Remove. Customizations cannot depend on each other. |
| cross-CUST reference | Move shared code to `lib/` and reference that instead. |
| hard-coded account ID (warn) | Use `data.aws_caller_identity.current.account_id`. |

## Manual checks the script cannot do

After the script passes, read the helper scripts once more and confirm:

- No `diff` branch exists; helpers are not run on diff. Only `apply` and
  `destroy` are handled.
- Every `aws` call that could fail is either tolerated (`|| true`, captured
  output) or is a genuine blocker that should `die`.
- `destroy` either reverts the feature or the README says it does not.
- The README's "Permissions" section matches the API calls actually made.

If `terraform plan` against a real sandbox account is possible, run it from
the `terraform/` directory with `-backend=false` init and a local state to
check for API-level errors the validator cannot see.
