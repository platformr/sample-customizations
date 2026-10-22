# CUST-CHANGE-ME

> One-line summary of what this customization does to the target account.

## What it does

- Bullet the account-level effect(s). Be concrete: which service, which
  setting, which region(s).

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/` | Resources Terraform manages (list them). |
| `api_helpers/pre-api-helpers.sh` | What runs before Terraform (or "context only"). |
| `api_helpers/post-api-helpers.sh` | Post-configuration and validation checks. |

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | Region to deploy into. |

Environment variables consumed by the helpers (beyond the standard AWS ones):

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |

## Permissions required by the deployment role

List the IAM actions the Platformr deployment role needs for this
customization (Terraform + helpers).

## Validation

Describe what `post-api-helpers.sh` checks and what a healthy run prints.

## Destroy behaviour

State what `terraform destroy` removes and whether the post helper reverts
anything Terraform cannot.

## References

- Link the AWS documentation this customization is based on.
