# CUST-transitive-network-spoke-account

> A spoke VPC in **one or two regions** for any workload account: its CIDR is
> allocated from the hub's shared IPAM environment pool and it is attached to
> the hub's Transit Gateway, so it joins the organization's transitive network
> the moment it is applied.

> **Dependency notice.** This customization **requires
> [`CUST-transitive-network-hub-account`](../CUST-transitive-network-hub-account/)
> to be applied in the networking account first**, with this account (or its
> OU, or the whole organization) as a principal of the hub's RAM shares. The
> repository normally forbids cross-customization dependencies; this hub/spoke
> pair is the sanctioned exception, because a spoke without a hub is
> meaningless. The pre helper checks the hub is visible and the Terraform
> precondition fails with a clear message if it is not.

**Regions:** set `spoke_regions` to one or two regions. Each must be one of
the hub's `hub_regions`; the spoke discovers that region's Transit Gateway
and pool. Two-region spokes get a VPC in each, reachable from each other and
from every other spoke through the hub's inter-region peering.

## What it does, per region

| Resource | Detail |
| --- | --- |
| VPC | CIDR allocated by IPAM from the hub pool `<hub_name_prefix>: <region> <environment>` (`/20` by default), DNS on, default security group emptied |
| Private workload subnets | one per AZ (`/22` from a `/20`), associated to a private route table |
| Transit subnets | one per AZ (`/28`), hold only the Transit Gateway attachment ENIs (AWS-recommended pattern) |
| Transit Gateway attachment | to the hub TGW found through the RAM share `<hub_name_prefix>-tgw-<region>`; the hub auto-accepts and propagates the VPC CIDR |
| Routes | `cloud_cidr` → TGW in both route tables; optionally `0.0.0.0/0` → TGW for centralised egress |
| SSM contract | VPC, subnets, route tables, attachment and pool IDs (see below) |

No internet gateway or NAT is created: egress and inspection are the hub's
responsibility (or add them in a follow-up customization in this account).

## Discovery (how the spoke finds the hub)

Spokes cannot read the networking account's SSM parameters or tags; they only
see what RAM shares with them. The spoke therefore relies on the hub's naming
contract:

| Need | Lookup |
| --- | --- |
| Transit Gateway in region `R` | RAM share `<hub_name_prefix>-tgw-<R>` in region `R`, `resource_owner = OTHER-ACCOUNTS` → TGW ARN |
| IPAM pool for `R` / `environment` | pools visible in `hub_home_region` with `locale == R` and `description == "<hub_name_prefix>: <R> <environment>"` |

`hub_name_prefix`, `hub_home_region`, `cloud_cidr` and `environment` must
match the hub's values. Defaults match the hub's defaults.

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/discovery.tf` | `aws_ram_resource_share` and `aws_vpc_ipam_pools` data sources; locals resolving TGW and pool IDs |
| `terraform/vpc.tf` | VPC (IPAM-allocated), subnets, route tables, locked default SG |
| `terraform/attachment.tf` | TGW attachment and routes |
| `terraform/ssm.tf` | SSM contract |
| `api_helpers/pre-api-helpers.sh` | apply: pending RAM invitations, hub TGW share ACTIVE per region, hub IPAM share ACTIVE. destroy: workload ENIs that block VPC deletion |
| `api_helpers/post-api-helpers.sh` | VPC `available`, attachment `available`, cloud route `active`, SSM contract and in-region copies |

Every region is handled with the provider's per-resource `region` argument;
no provider aliases.

## SSM parameters

Home-region prefix: **`/platformr/CUST-transitive-network-spoke-account/`**

| Parameter | Type | Value |
| --- | --- | --- |
| `regions` | StringList | spoke regions |
| `environment` | String | hub environment used |
| `cloud_cidr`, `hub_name_prefix`, `hub_home_region` | String | hub contract values used |
| `<region>/vpc_id` | String | |
| `<region>/vpc_cidr` | String | CIDR IPAM allocated |
| `<region>/private_subnet_ids` | StringList | workload subnets |
| `<region>/transit_subnet_ids` | StringList | attachment subnets (do not use for workloads) |
| `<region>/availability_zones` | StringList | in subnet order |
| `<region>/private_route_table_id` | String | |
| `<region>/transit_route_table_id` | String | |
| `<region>/transit_gateway_id` | String | hub TGW discovered |
| `<region>/transit_gateway_attachment_id` | String | |
| `<region>/ipam_pool_id` | String | hub pool discovered |

In **each spoke region** additionally: `vpc_id` (String) and
`private_subnet_ids` (StringList).

A workload customization in this account consumes them like this:

```hcl
data "aws_ssm_parameter" "vpc_id" {
  name = "/platformr/CUST-transitive-network-spoke-account/vpc_id" # in-region copy
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/platformr/CUST-transitive-network-spoke-account/private_subnet_ids"
}

locals {
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
}
```

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `spoke_regions` | `["us-east-1"]` | **One or two** hub regions to build a VPC in. |
| `environment` | `development` | Hub environment pool to allocate from. |
| `hub_name_prefix` | `network-hub` | Must equal the hub's `name_prefix`. |
| `hub_home_region` | `us-east-1` | Must equal the hub's `region`. |
| `cloud_cidr` | `172.16.0.0/12` | Must equal the hub's `cloud_cidr`. |
| `vpc_netmask_length` | `20` | 16–20; within the pool's allocation min/max. |
| `availability_zone_count` | `2` | 1–3. |
| `route_default_via_transit_gateway` | `false` | Send `0.0.0.0/0` to the hub. |
| `enable_dns_hostnames` | `true` | |
| `name_prefix` | `spoke` | Names and tags. |
| `region` | `us-east-1` | Home region of the SSM contract only. |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `SPOKE_REGIONS` | from SSM, else `us-east-1` | Needed on the first apply when SSM is empty; keep equal to `spoke_regions`. |
| `HUB_NAME_PREFIX` | from SSM, else `network-hub` | |
| `HUB_HOME_REGION` | from SSM, else `us-east-1` | |
| `CUSTOMIZATION_NAME` | directory name | SSM path prefix. |

## Permissions required by the deployment role

```
ram:GetResourceShares, ram:GetResourceShareInvitations, ram:ListResources
ec2:DescribeIpamPools, ec2:AllocateIpamPoolCidr, ec2:ReleaseIpamPoolAllocation
  (allocation happens implicitly through CreateVpc with an IPAM pool)
ec2:CreateVpc, ec2:DeleteVpc, ec2:DescribeVpcs, ec2:ModifyVpcAttribute, ec2:DescribeVpcAttribute,
ec2:CreateSubnet, ec2:DeleteSubnet, ec2:DescribeSubnets,
ec2:CreateRouteTable, ec2:DeleteRouteTable, ec2:DescribeRouteTables, ec2:AssociateRouteTable,
ec2:DisassociateRouteTable, ec2:CreateRoute, ec2:DeleteRoute,
ec2:DescribeSecurityGroups, ec2:RevokeSecurityGroupIngress, ec2:RevokeSecurityGroupEgress,
ec2:CreateTransitGatewayVpcAttachment, ec2:DeleteTransitGatewayVpcAttachment,
ec2:DescribeTransitGatewayVpcAttachments, ec2:DescribeTransitGatewayAttachments,
ec2:DescribeNetworkInterfaces, ec2:DescribeAvailabilityZones, ec2:CreateTags, ec2:DeleteTags,
ssm:PutParameter, ssm:GetParameter, ssm:DeleteParameter, ssm:AddTagsToResource, ssm:ListTagsForResource
```

## Validation

```
[ OK ] SSM environment: development
[ OK ] us-east-1: VPC vpc-0abc state: available
[ OK ] us-east-1: VPC CIDR (from IPAM): 172.18.0.0/20
[ OK ] us-east-1: TGW attachment tgw-attach-… state: available
[ OK ] us-east-1: route 172.16.0.0/12 -> TGW state: active
[ OK ] us-east-1: in-region SSM vpc_id: vpc-0abc
[ OK ] us-east-1: SSM private_subnet_ids: subnet-…,subnet-…
```

## Destroy behaviour

`terraform destroy` detaches from the Transit Gateway, deletes routes,
subnets and the VPC (IPAM releases the CIDR automatically), and removes the
SSM contract. Workloads still running in the VPC (ENIs) block subnet/VPC
deletion; the pre helper lists them on destroy. The hub is untouched.

## References

- [`CUST-transitive-network-hub-account`](../CUST-transitive-network-hub-account/README.md) (discovery contract)
- [Transit Gateway VPC attachments](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-vpc-attachments.html)
- [Create a VPC from a shared IPAM pool](https://docs.aws.amazon.com/vpc/latest/ipam/tutorials-get-started-console.html)
