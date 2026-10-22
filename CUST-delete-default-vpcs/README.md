# CUST-delete-default-vpcs

> Delete the default VPC in every enabled region of the account. The work is
> done by the **pre** helper, verified by the **post** helper, and recorded
> in SSM. Terraform manages only the SSM marker.

This is the example of a customization whose substance is API work, not
infrastructure: Terraform has nothing sensible to "own" for a deletion, so
it just leaves a discoverable record that the account has been swept.

## What it does

1. **`pre-api-helpers.sh` (apply)**: for every enabled region, if a default
   VPC exists, detach and delete its internet gateway, delete its subnets,
   then delete the VPC. Default route tables, NACLs and the default security
   group go with it. Regions without a default VPC are skipped, so re-running
   is harmless.
2. **`terraform apply`**: writes two SSM marker parameters (below).
3. **`post-api-helpers.sh` (apply)**: re-checks every enabled region, prints
   `[ OK ]`/`[FAIL]` per region, and records the outcome in two more SSM
   parameters.

Adapted from the Cloud Foundations on AWS
[default VPC deletion script](https://github.com/cloud-foundations-on-aws/cloud-foundations-templates/blob/main/network/network-default-vpc-deletion/script-network-default-vpc-deletion.sh),
with the `jq` dependency removed, idempotent skips, per-region error
isolation, and dry-run / region-filter switches.

## Why delete default VPCs

Default VPCs come with public subnets that auto-assign public IPs and a
permissive default security group. Removing them is a common landing-zone
baseline (CIS / Well-Architected) so that every network in the account is
deliberately designed. Do it before workloads land; afterwards anything in a
default VPC blocks deletion.

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `api_helpers/pre-api-helpers.sh` | Region sweep and deletion (apply only) |
| `terraform/main.tf` | `aws_ssm_parameter` `enabled` and `scope` markers |
| `api_helpers/post-api-helpers.sh` | Region sweep verification; writes `last_validation*` SSM parameters; removes them on destroy |

## SSM parameters

All under **`/platformr/CUST-delete-default-vpcs/`**:

| Parameter | Owner | Value |
| --- | --- | --- |
| `enabled` | Terraform | `true` once the customization has been applied |
| `scope` | Terraform | `all-enabled-regions` |
| `last_validation_status` | post helper | `PASS` when no default VPC remained at the last apply, otherwise `FAIL` |
| `last_validation` | post helper | `regions_checked=<n>;remaining=<region:vpc-id ...|none>;checked_at=<UTC timestamp>` |

Other customizations or pipelines can gate on `enabled` + `last_validation_status`.

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | Where the SSM markers live. The sweep is account-wide regardless. |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `DEFAULT_VPC_REGIONS` | all enabled regions | Space-separated list to limit the sweep and the check (e.g. `"us-east-1 us-west-2"`). |
| `DEFAULT_VPC_DRY_RUN` | `false` | `true` makes the pre helper report what it would delete without deleting. |
| `CUSTOMIZATION_NAME` | `CUST-delete-default-vpcs` | SSM path prefix. |

## Permissions required by the deployment role

```
ec2:DescribeRegions, ec2:DescribeVpcs, ec2:DescribeInternetGateways, ec2:DescribeSubnets,
ec2:DetachInternetGateway, ec2:DeleteInternetGateway, ec2:DeleteSubnet, ec2:DeleteVpc,
ssm:PutParameter, ssm:GetParameter, ssm:DeleteParameter, ssm:AddTagsToResource, ssm:ListTagsForResource
```

## Validation

```
[ OK ] us-east-1: no default VPC
[ OK ] us-east-2: no default VPC
[FAIL] eu-west-1: default VPC still present (vpc-0123456789abcdef0)
...
[FAIL] Default VPCs remain: eu-west-1:vpc-0123456789abcdef0
[ OK ] SSM /platformr/CUST-delete-default-vpcs/last_validation_status = FAIL
```

A `FAIL` almost always means something is still running inside that default
VPC (instance, ENI, NAT gateway, endpoint, load balancer). The pre helper's
`delete-vpc` error names the dependency. Clean it up and re-apply.

## Destroy behaviour

`terraform destroy` removes the two marker parameters and the post helper
removes the two validation parameters. **Deleted default VPCs are not
recreated.** If an account needs one back, run
`aws ec2 create-default-vpc --region <region>` manually.

## References

- [Default VPCs](https://docs.aws.amazon.com/vpc/latest/userguide/default-vpc.html) (including deleting and recreating)
- [Cloud Foundations on AWS: default VPC deletion](https://github.com/cloud-foundations-on-aws/cloud-foundations-templates/tree/main/network/network-default-vpc-deletion)
