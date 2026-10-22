# CUST-ec2-ebs-encryption-by-default

> Turn on Amazon EBS encryption by default for the target region, optionally
> with a customer-managed KMS key as the region's default EBS key.

## What it does

- Enables **EBS encryption by default** in `var.region`. Every new EBS
  volume and every snapshot copy created in that region is encrypted
  automatically, even when the caller does not ask for it.
- Optionally sets `var.default_kms_key_arn` as the region's default EBS
  encryption key. When unset, the AWS managed key `aws/ebs` is used.

This is a **per-region** setting. Run the customization once per region you
want covered. It has no effect on existing volumes or snapshots; see the AWS
docs for how to re-encrypt those.

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/main.tf` | `aws_ebs_encryption_by_default`, optional `aws_ebs_default_kms_key` |
| `api_helpers/pre-api-helpers.sh` | Prints the current setting and default key (context only) |
| `api_helpers/post-api-helpers.sh` | `get-ebs-encryption-by-default` must be `True`; reports the default key |

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | Region to enable in. |
| `default_kms_key_arn` | `null` | Customer-managed key ARN. The key must be symmetric and its policy must allow EC2/EBS to use it. |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `EXPECT_DEFAULT_KMS_KEY` | (empty) | If set, the post helper asserts the default key equals this value. |

## Permissions required by the deployment role

```
ec2:GetEbsEncryptionByDefault, ec2:EnableEbsEncryptionByDefault, ec2:DisableEbsEncryptionByDefault,
ec2:GetEbsDefaultKmsKeyId, ec2:ModifyEbsDefaultKmsKeyId, ec2:ResetEbsDefaultKmsKeyId
```

## Considerations

- Once enabled for a region you cannot opt individual volumes out.
- Launching from an unencrypted AMI still works; the resulting volumes are
  encrypted with the default key.
- If you set a customer-managed key, make sure principals that create
  volumes (including service roles like Auto Scaling) can use the key, or
  launches fail.

## Validation

```
[ OK ] EBS encryption by default (us-east-1): True
[ OK ] Default EBS KMS key: alias/aws/ebs
```

## Destroy behaviour

`terraform destroy` disables encryption by default and resets the default
key to `aws/ebs`. Volumes created while it was enabled stay encrypted. The
post helper confirms the setting reads `False`.

## References

- [Enable Amazon EBS encryption by default](https://docs.aws.amazon.com/ebs/latest/userguide/encryption-by-default.html)
- [Amazon EBS encryption](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-encryption.html)
- Terraform: [`aws_ebs_encryption_by_default`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_encryption_by_default),
  [`aws_ebs_default_kms_key`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_default_kms_key)
