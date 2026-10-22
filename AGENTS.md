# Platformr Customizations — agent instructions

This repository holds **Platformr Customizations**: self-contained Terraform
deployments, one per `CUST-<suffix>` directory, that Platformr runs against a
target AWS account. Read this file before changing anything.

## Skills

Procedures live as Agent Skills (`SKILL.md` files) in **`skills/`**, the
single source of truth. `.claude/skills`, `.agents/skills` and `.kiro/skills`
are symlinks to it, so Claude Code, Codex, Gemini CLI, Cursor, Copilot and
Kiro all discover the same files (see `skills/README.md`; run
`scripts/link-skills.sh all` for other agents).

**If your agent has native skill support**, let it load the matching skill.
**If it does not**, open the file directly and follow it:

| Skill | File | Use when |
| --- | --- | --- |
| `create-customization` | `skills/create-customization/SKILL.md` | Adding a new `CUST-*` directory or implementing an AWS feature enablement |
| `write-api-helpers` | `skills/write-api-helpers/SKILL.md` | Writing or reviewing `pre-api-helpers.sh`, `post-api-helpers.sh`, python helpers |
| `validate-customization` | `skills/validate-customization/SKILL.md` | After any edit under `CUST-*` or `_TEMPLATE/`; before committing |

## How a customization is executed

For one target account, one customization, one action (`apply`, `diff`,
`destroy`):

```
# apply / destroy
git clone <this repo>
cd CUST-<suffix>/api_helpers && ./pre-api-helpers.sh
cd ../terraform              && terraform init && terraform <apply|destroy>
cd ../api_helpers            && ./post-api-helpers.sh

# diff  (Terraform only; helpers are NOT run)
git clone <this repo>
cd CUST-<suffix>/terraform   && terraform init && terraform plan
```

- The build injects AWS credentials for the target account, the Terraform
  backend configuration, and `PLATFORMR_ACTION=<apply|destroy>` for the
  helper scripts.
- **A `diff` runs only the infrastructure-as-code portion (`terraform plan`).
  `pre-api-helpers.sh` and `post-api-helpers.sh` are never executed on a
  diff.** Helper scripts therefore handle `apply` and `destroy` only.
- Many sessions may run concurrently, each for a different account or
  customization. **There is no ordering between customizations.**
- The same customization may be applied to the same account repeatedly.

## Repository layout

```
_TEMPLATE/                 Starting point for every new customization (do not deploy)
CUST-<suffix>/             One customization
  README.md                What / how / inputs / permissions / validation / destroy
  api_helpers/
    pre-api-helpers.sh     Runs before terraform
    post-api-helpers.sh    Runs after terraform (configuration + validation)
    python/                Optional python helpers + requirements.txt
  terraform/               Terraform root module (entry point: all *.tf files)
lib/                       Shared code any customization may use (lib/bash/common.sh)
scripts/                   Repo tooling: new-customization.sh, validate-customization.sh
skills/                    Agent skills (SKILL.md) for any AI coding agent; .claude/.agents/.kiro link here
```

## Hard rules

1. **Naming.** Top-level directory `CUST-<suffix>`; suffix is letters, digits
   and dashes. Everything else at top level is not a customization.
2. **No cross-customization dependencies.** No `terraform_remote_state`, no
   sourcing files from another `CUST-*`, no assuming another customization
   ran first. Shared code goes in `lib/`.
3. **No backend block** in Terraform. Platformr injects it.
4. **Idempotent.** `apply` twice must converge with no errors; helpers must
   check-before-change.
5. **Helpers do not run on `diff`.** A diff is `terraform plan` only. Do not
   write `diff` branches in helpers, and do not rely on a helper for anything
   a plan needs to show.
6. **No hard-coded account IDs or ARNs.** Use `data.aws_caller_identity`,
   `data.aws_partition`, `data.aws_region` in Terraform and `aws_account_id`
   / `aws_region` from `lib/bash/common.sh` in helpers.
7. **Prefer Terraform.** Use a provider resource when one exists (provider
   `>= 6.0`). Use helpers only for API calls Terraform cannot express and for
   validation.
8. **Validation reports, it does not fail.** Post helpers echo
   `[ OK ]`/`[FAIL]` lines and let the build finish.
9. **Terraform → helper hand-off via SSM.** If a helper needs a value only
   Terraform knows, Terraform writes `aws_ssm_parameter` under
   `/platformr/<CUST-name>/...`; helpers read it. Never read state from helpers.
10. **Destroy must be honest.** If Terraform cannot revert a setting, the post
    helper reverts it on `destroy` or the README says it stays.
11. **Always run `scripts/validate-customization.sh`** (terraform fmt,
    terraform validate, shell/python syntax, layout, anti-patterns) before
    finishing.

## Conventions

- Terraform files: `versions.tf`, `providers.tf`, `variables.tf`, `data.tf`,
  `main.tf`, `outputs.tf`; add topic files (`iam.tf`) as needed.
- Variables have descriptions, defaults, and `validation` blocks for
  constrained values. `var.customization_name` defaults to the directory name.
- Policies via `data.aws_iam_policy_document`, not JSON heredocs.
- Helper scripts: `set -euo pipefail`, source `lib/bash/common.sh`, call
  `print_aws_context`, dispatch on `customization_action`.
- Each README lists the IAM actions the deployment role needs.
- Keep READMEs current; they are documentation for humans and for agents.

## Tooling expected on the build image

Terraform >= 1.5, AWS CLI v2 (recent enough for the services used), bash,
python3 (for python helpers). The validator additionally benefits from
`shellcheck` and `tflint` when present.
