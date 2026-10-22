# CUST-enforce-imdsv2-on-account

> Require IMDSv2 for all new EC2 instances in the region at the account
> level, and enforce it so launches that try to enable IMDSv1 fail.

## What it does

Two account-level, per-region settings from the EC2 "IMDS defaults" page:

1. **Default to IMDSv2** (`HttpTokens=required`, `HttpEndpoint=enabled`,
   hop limit `var.http_put_response_hop_limit`). New instances launch with
   IMDSv2 required unless the launch explicitly overrides it. Managed by
   Terraform.
2. **Enforce IMDSv2** (`HttpTokensEnforced=enabled`). Instances can only
   launch if IMDSv2 is required, regardless of launch template or AMI
   settings. The Terraform AWS provider (v6.69) does not expose this flag,
   so the post helper sets it with
   `aws ec2 modify-instance-metadata-defaults --http-tokens-enforced enabled`
   when `var.enforce` is true.

Neither setting changes **existing** instances. This is per-region; deploy
once per region.

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/main.tf` | `aws_ec2_instance_metadata_defaults` + SSM parameter `/platformr/CUST-enforce-imdsv2-on-account/enforce` |
| `api_helpers/pre-api-helpers.sh` | Shows current defaults; fails loudly if a declarative policy owns them; warns if the CLI is too old for `--http-tokens-enforced` |
| `api_helpers/post-api-helpers.sh` | Sets `HttpTokensEnforced` (apply) or clears it (destroy); validates with `get-instance-metadata-defaults` |

This customization is the model for "Terraform does most of it, the helper
does the one API flag the provider lacks".

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | Region to configure. |
| `http_put_response_hop_limit` | `2` | AWS recommends 2 for container hosts; `-1` = no preference. |
| `instance_metadata_tags` | `no-preference` | `enabled`, `disabled` or `no-preference`. |
| `enforce` | `true` | Also set `HttpTokensEnforced=enabled` via the post helper. |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `CUSTOMIZATION_NAME` | `CUST-enforce-imdsv2-on-account` | SSM path prefix. |

## Permissions required by the deployment role

```
ec2:GetInstanceMetadataDefaults, ec2:ModifyInstanceMetadataDefaults,
ssm:PutParameter, ssm:GetParameter, ssm:DeleteParameter, ssm:AddTagsToResource, ssm:ListTagsForResource
```

## Before enabling enforcement

Make sure AMIs and applications in the account support IMDSv2 (see the AWS
"recommended path to requiring IMDSv2"). With enforcement on, any launch
whose effective `HttpTokens` is `optional` fails. If an Organizations
declarative policy manages IMDS defaults, the account cannot change them and
this customization will fail; the pre helper reports that case.

## Validation

```
[ OK ] AccountLevel.HttpTokens: required
[ OK ] AccountLevel.HttpEndpoint: enabled
[ OK ] AccountLevel.HttpPutResponseHopLimit: 2
[ OK ] AccountLevel.HttpTokensEnforced: enabled
[INFO] ManagedBy: account
```

## Destroy behaviour

`terraform destroy` resets the account defaults to no preference. The post
helper then disables `HttpTokensEnforced` and validates both. Existing
instances are untouched either way.

## Build image requirement

`--http-tokens-enforced` needs a recent AWS CLI v2. Older CLIs make the
helper log a warning and skip enforcement; the Terraform-managed defaults
still apply.

## References

- [Configure instance metadata options for new instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-IMDS-new-instances.html#enforce-imdsv2-at-the-account-level)
- Terraform: [`aws_ec2_instance_metadata_defaults`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_instance_metadata_defaults)
