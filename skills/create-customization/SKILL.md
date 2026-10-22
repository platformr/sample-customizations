---
name: create-customization
description: Create a new Platformr Customization (a CUST-<suffix> directory with terraform/ and api_helpers/) from _TEMPLATE. Use when asked to add, scaffold, build or implement a customization, or to enable/configure an AWS feature per account through this repo.
---

# Create a Platformr Customization

A customization is one top-level directory named `CUST-<suffix>` that Platformr
clones, then runs in a target account as:

1. `api_helpers/pre-api-helpers.sh` (apply and destroy only)
2. `terraform <apply|plan|destroy>` inside `terraform/`
3. `api_helpers/post-api-helpers.sh` (apply and destroy only)

On a `diff` only step 2 runs (`terraform plan`); the helpers are skipped.

Read `/AGENTS.md` first for the repository rules. The summary that matters here:
**one account, one region, one customization per run; no dependencies between
customizations; everything must be safe to run repeatedly.**

## Procedure

1. **Pick a name.** `CUST-` + short kebab-case feature name
   (`CUST-guardduty`, `CUST-transaction-search`). Letters, digits, dashes only.

2. **Scaffold from the template.**
   ```bash
   scripts/new-customization.sh <suffix> "One-line description"
   ```
   This copies `_TEMPLATE/`, replaces `CUST-CHANGE-ME`, and makes the helper
   scripts executable. Never hand-copy the template; never edit `_TEMPLATE/`
   for a specific feature.

3. **Research the feature before writing code.** Find the AWS documentation
   for the feature and answer:
   - Which API calls enable it? (console steps map to APIs)
   - Does the Terraform AWS provider (`>= 6.0`) have a resource for each call?
     Check `https://registry.terraform.io/providers/hashicorp/aws/latest/docs`.
     If unsure, run `terraform providers schema -json` (or `tofu providers
     schema -json`) in an initialised directory and grep for the resource name.
   - Which parts are account-level (belong here) vs. per-workload (do not)?
   - What does "destroy" mean for this feature, and can Terraform revert it?
   - Which IAM actions does the deployment role need?

4. **Decide the split** between Terraform and helpers:
   | Put it in | When |
   | --- | --- |
   | `terraform/` | A provider resource exists. Always prefer this. |
   | `post-api-helpers.sh` | API-only settings after resources exist; validation. |
   | `pre-api-helpers.sh` | Pre-conditions, opt-ins that must precede Terraform. |
   | `api_helpers/python/` | Logic that is clumsy in bash / needs boto3. |

5. **Write Terraform** in `terraform/`:
   - Keep `versions.tf`, `providers.tf`, `variables.tf`, `data.tf`, `outputs.tf`
     from the template; put resources in `main.tf` (split into more files if
     large).
   - Use `data.aws_caller_identity`, `data.aws_partition`, `data.aws_region`
     instead of hard-coded IDs/ARNs.
   - Build IAM/resource policies with `data.aws_iam_policy_document`, not
     heredoc JSON.
   - Set `var.customization_name` default to the directory name.
   - Give every variable a `description`, a sensible `default`, and a
     `validation` block when values are constrained (e.g. allowed regions).
   - If the post helper needs a value Terraform knows (an ID, an ARN), write
     it to an SSM parameter under `/platformr/<CUST-name>/...` and read it back
     in the helper. Do not read Terraform state from helpers.
   - No `backend` block. No `terraform_remote_state`.
   - Read the resource docs for destroy semantics; some resources are no-op on
     delete (e.g. `aws_xray_trace_segment_destination`). Revert those in the
     post helper on `destroy` if the customization's intent requires it.

6. **Write helpers** following the `write-api-helpers` skill. At minimum the
   post helper has one `validate_*` function per effect that prints
   `[ OK ]`/`[FAIL]` and never aborts the build.

7. **Write `README.md`** using the template's headings: what it does, how it
   is implemented, inputs, permissions, validation, destroy behaviour,
   references. Link the AWS docs you used.

8. **Validate.** Run the `validate-customization` skill
   (`scripts/validate-customization.sh CUST-<suffix>`) and fix everything it
   reports. `fmt` and `validate` must pass (Terraform or OpenTofu; the script
   auto-detects, or set `TF_CLI`).

9. **Add the customization to the table in the root `README.md`.**

## Checklist before you call it done

- [ ] Directory is `CUST-<suffix>`, built from `_TEMPLATE`
- [ ] No references to other `CUST-*` directories; only `lib/` is shared
- [ ] Terraform: fmt + validate clean, no backend block, no hard-coded account IDs
- [ ] Helpers: idempotent, handle `apply` and `destroy` only (not run on `diff`), validation echoes status
- [ ] README filled in, root README table updated
- [ ] Permissions the deployment role needs are listed
