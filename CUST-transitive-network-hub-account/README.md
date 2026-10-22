# CUST-transitive-network-hub-account

> The organization's shared network hub: a Transit Gateway in **one or two
> regions** (peered when there are two, so the network is transitive across
> regions), a hierarchical IPAM (cloud → region → environment) whose
> environment pools are shared to the organization, and an SSM contract that
> describes all of it.

> **Deploy this to exactly one account: the networking account.** It owns the
> organization's Transit Gateways and IPAM; every other account consumes them
> through RAM. Running it in a second account would create a second,
> competing hub. The companion
> [`CUST-transitive-network-spoke-account`](../CUST-transitive-network-spoke-account/)
> is what every *other* account deploys to get a VPC wired into this hub.

**Regions:** set `hub_regions` to one or two regions. One region gives a
single Transit Gateway and pool tree; two gives both plus inter-region
peering and summary routes. The spoke customization must use the same
region(s).

> **Platformr Foundation users:** if Platformr Foundation is deployed, deploy
> this customization into the account provisioned by the Foundation's
> **networking capability**. That capability creates the network account and
> completes the organization-level prerequisites below (RAM sharing with
> Organizations, IPAM delegated administrator), so you only need to set the
> variables and apply.

## Prerequisites

Done once, from the **organization management account** (the Foundation
networking capability does these for you):

1. **RAM sharing with AWS Organizations enabled**
   `aws ram enable-sharing-with-aws-organization`
   Required to share Transit Gateways and IPAM pools with the organization
   ARN instead of listing accounts.
2. **This account is the IPAM delegated administrator**
   `aws ec2 enable-ipam-organization-admin-account --delegated-admin-account-id <network-account-id>`
   Required for IPAM to integrate with Organizations and for pool sharing to
   work.

In the **network account** (checked by the pre helper):

3. The account is a member of the organization.
4. Every region in `hub_regions` is enabled.
5. No other IPAM exists in the home region (one IPAM per region).

Planning decisions before the first apply (changing them later means
re-addressing):

6. **CIDR plan.** `cloud_cidr` must not overlap on-premises or partner
   ranges; each region's `cidr` must sit inside it; environments split each
   region CIDR equally.
7. **Unique private ASNs** per Transit Gateway, also unique against any
   on-premises or Direct Connect gateway ASNs.
8. **IPAM tier.** Organization integration and pool sharing need the
   **advanced** tier, billed per active IP address managed. `free` only
   suits a single-account lab.

## What it does

| Area | Resources | Notes |
| --- | --- | --- |
| Transit Gateways | `aws_ec2_transit_gateway` per hub region | Unique ASN, auto-accept shared attachments, default route-table association + propagation (everything transitive by default), DNS and VPN ECMP on |
| Inter-region peering | `aws_ec2_transit_gateway_peering_attachment` + `_accepter` per region pair, `aws_ec2_transit_gateway_route` per side | Full mesh. Static route for the peer region's summary CIDR on each default route table, so a spoke in region A reaches a spoke in region B via the two hubs |
| IPAM | `aws_vpc_ipam` (home region, all hub regions as operating regions), pools: cloud → region → environment | Environment pools carry allocation defaults (`/20` by default, `/16`–`/28` allowed) so a spoke VPC can simply ask for "a CIDR from production in us-east-1" |
| Sharing | `aws_ram_resource_share` per region for its TGW; one share in the home region for all environment pools | Principals default to the organization ARN; override with `ram_principals` (OU ARNs or accounts) |
| Contract | `aws_ssm_parameter` set in the home region plus a per-region `transit_gateway_id` | See "SSM parameters" |

Default IP plan (`cloud_cidr = 172.16.0.0/12`, two regions, four environments):

| Region | Region CIDR | production | development | management | shared-services |
| --- | --- | --- | --- | --- | --- |
| us-east-1 | 172.16.0.0/13 | 172.16.0.0/15 | 172.18.0.0/15 | 172.20.0.0/15 | 172.22.0.0/15 |
| us-west-2 | 172.24.0.0/13 | 172.24.0.0/15 | 172.26.0.0/15 | 172.28.0.0/15 | 172.30.0.0/15 |

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/tgw.tf` | Transit Gateways, peering mesh, static summary routes |
| `terraform/ipam.tf` | IPAM and the three-level pool hierarchy |
| `terraform/ram.tf` | RAM shares and principal associations |
| `terraform/ssm.tf` | SSM contract |
| `api_helpers/pre-api-helpers.sh` | apply: org membership, regions enabled, foreign-IPAM check, prerequisite reminder. destroy: lists spoke attachments and IPAM allocations that will block deletion |
| `api_helpers/post-api-helpers.sh` | TGWs `available`, RAM shares `ACTIVE`, peering attachments `available`, every IPAM pool `create-complete` with CIDR `provisioned`, in-region SSM copies correct |

All regions are driven from one map (`hub_regions`) using the AWS provider's
per-resource `region` argument (provider ≥ 6). Adding a hub region is one
map entry; no provider aliases, no copied blocks.

### Refactor notes (vs. the original AFT customization)

The original was written for a single AFT provider region and hand-copied
per region. Changes made here:

- **Multi-region for real.** The original only built a us-west-2 TGW (in
  whatever region the provider pointed at). Now every region in `hub_regions`
  gets a TGW, a RAM share and IPAM pools, plus inter-region peering with
  summary routes, which the original did not have.
- **IPAM pool bugs fixed.** Several environment CIDRs were provisioned into
  the *region* pool or the *production* pool instead of their own pool
  (copy-paste `ipam_pool_id` references). Pools are now generated from a
  map, so a CIDR always lands in its own pool.
- **RAM principal.** The original passed the organization *ID* (`o-…`) as a
  principal, which RAM rejects; the organization *ARN* is used, read from
  `aws_organizations_organization`.
- **Everything shared.** Only one region's pool was shared before; now every
  region's environment pools and every TGW are shared.
- **Removed** the unused custom TGW route table, the unused `az_index`
  variable, the `FOTF` naming, and dash-named variables.
- **Added** validation blocks (unique ASNs, private ASN ranges, valid CIDRs),
  tags, allocation netmask defaults, descriptions, outputs, helpers and the
  SSM contract.

## SSM parameters

Home-region prefix: **`/platformr/CUST-transitive-network-hub-account/`**
(`<region>` is a hub region, `<env>` an environment name, `<a>--<b>` a
region pair in sorted order).

| Parameter | Type | Value |
| --- | --- | --- |
| `hub_regions` | StringList | hub regions, sorted |
| `environments` | StringList | environment names in pool order |
| `ram_principals` | StringList | principals the hub is shared with |
| `organization_arn` | String | organization ARN |
| `home_region` | String | IPAM / contract region |
| `cloud_cidr` | String | top-level CIDR |
| `vpc_allocation_netmask` | String | `default=20;min=16;max=28` |
| `transit_gateway/<region>/id` | String | `tgw-…` |
| `transit_gateway/<region>/arn` | String | |
| `transit_gateway/<region>/asn` | String | |
| `transit_gateway/<region>/route_table_id` | String | default association route table |
| `transit_gateway/<region>/ram_share_arn` | String | |
| `transit_gateway/<region>/cidr` | String | region summary CIDR |
| `transit_gateway/peering/<a>--<b>/attachment_id` | String | peering attachment (requester side) |
| `ipam/id`, `ipam/arn`, `ipam/private_scope_id`, `ipam/tier` | String | |
| `ipam/pool/cloud/id`, `ipam/pool/cloud/arn` | String | level-1 pool |
| `ipam/pool/<region>/id`, `/arn`, `/cidr` | String | level-2 pools |
| `ipam/pool/<region>/<env>/id`, `/arn`, `/cidr` | String | level-3 pools (the ones spokes allocate from) |
| `ipam/ram_share_arn` | String | share containing all environment pools |

In **each hub region** additionally:

| Parameter | Type | Value |
| --- | --- | --- |
| `transit_gateway_id` | String | the TGW serving that region |

### Discovery contract for spoke accounts

Spokes cannot read this account's SSM parameters or resource tags; they see
the hub through RAM. These **names are therefore part of the contract** and
`CUST-transitive-network-spoke-account` relies on them. Changing
`name_prefix` after spokes exist breaks their discovery.

| What a spoke looks up | Where | Value |
| --- | --- | --- |
| Transit Gateway for region `R` | RAM share named `<name_prefix>-tgw-<R>` in region `R` (`resource_owner = OTHER-ACCOUNTS`) | share lists the TGW ARN |
| Environment pool for region `R`, environment `E` | IPAM pools visible in the **hub home region**, matching `locale = R` and `description = "<name_prefix>: <R> <E>"` | pool ID to allocate the VPC CIDR from |
| Cloud summary route | spoke variable `cloud_cidr` (must equal this hub's `cloud_cidr`) | route target for the TGW attachment |

With defaults: `network-hub-tgw-us-east-1`, `network-hub-ipam-pools`,
`network-hub: us-east-1 production`.

Use the spoke customization rather than hand-writing this; the snippet below
shows the mechanism only.

```hcl
data "aws_ram_resource_share" "tgw" {
  name           = "network-hub-tgw-us-east-1"
  resource_owner = "OTHER-ACCOUNTS"
}

data "aws_vpc_ipam_pools" "shared" {
  region = "us-east-1" # hub home region
}

locals {
  tgw_id  = element(split("/", one([for a in data.aws_ram_resource_share.tgw.resource_arns : a if can(regex(":transit-gateway/", a))])), 1)
  pool_id = one([for p in data.aws_vpc_ipam_pools.shared.ipam_pools : p.id if p.locale == "us-east-1" && p.description == "network-hub: us-east-1 production"])
}
```

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | Home region (IPAM, IPAM share, contract). |
| `name_prefix` | `network-hub` | Names and `Name` tags. |
| `hub_regions` | us-east-1 (64512, 172.16.0.0/13), us-west-2 (64513, 172.24.0.0/13) | **One or two** regions with ASN and summary CIDR. Remove an entry for single-region. |
| `cloud_cidr` | `172.16.0.0/12` | |
| `environments` | production, development, management, shared-services | Equal split of each region CIDR, in order. |
| `vpc_allocation_netmask` | default 20, min 16, max 28 | Allocation rules on environment pools. |
| `ipam_tier` | `advanced` | `free` for single-account labs only. |
| `ram_principals` | `[]` (= organization) | OU ARNs / account IDs to share with instead. |
| `enable_transit_gateway_peering` | `true` | Full-mesh inter-region peering + routes. |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `NETWORK_HUB_REGIONS` | from SSM, else `us-east-1 us-west-2` | Keep in sync with `hub_regions` for the first apply and for destroy. |
| `CUSTOMIZATION_NAME` | directory name | SSM path prefix. |

## Permissions required by the deployment role

```
organizations:DescribeOrganization
ec2:CreateTransitGateway, ec2:DeleteTransitGateway, ec2:DescribeTransitGateways, ec2:ModifyTransitGateway,
ec2:CreateTransitGatewayPeeringAttachment, ec2:AcceptTransitGatewayPeeringAttachment,
ec2:DeleteTransitGatewayPeeringAttachment, ec2:DescribeTransitGatewayPeeringAttachments,
ec2:DescribeTransitGatewayAttachments, ec2:DescribeTransitGatewayRouteTables,
ec2:CreateTransitGatewayRoute, ec2:DeleteTransitGatewayRoute, ec2:SearchTransitGatewayRoutes,
ec2:CreateIpam, ec2:DeleteIpam, ec2:DescribeIpams, ec2:ModifyIpam, ec2:DescribeIpamScopes,
ec2:CreateIpamPool, ec2:DeleteIpamPool, ec2:DescribeIpamPools, ec2:ModifyIpamPool,
ec2:ProvisionIpamPoolCidr, ec2:DeprovisionIpamPoolCidr, ec2:GetIpamPoolCidrs, ec2:GetIpamPoolAllocations,
ec2:PutResourcePolicy, ec2:DeleteResourcePolicy      (IPAM pool sharing)
ec2:CreateTags, ec2:DeleteTags, ec2:DescribeRegions,
ram:CreateResourceShare, ram:DeleteResourceShare, ram:GetResourceShares, ram:UpdateResourceShare,
ram:AssociateResourceShare, ram:DisassociateResourceShare, ram:GetResourceShareAssociations,
ram:TagResource, ram:UntagResource,
ssm:PutParameter, ssm:GetParameter, ssm:GetParametersByPath, ssm:DeleteParameter,
ssm:AddTagsToResource, ssm:ListTagsForResource
```

## Validation

```
[ OK ] us-east-1: tgw-0abc state: available
[ OK ] us-east-1: TGW RAM share status: ACTIVE
[ OK ] us-east-1: in-region SSM transit_gateway_id: tgw-0abc
[ OK ] us-west-2: tgw-0def state: available
...
[ OK ] Peering us-east-1--us-west-2 (tgw-attach-…) state: available
[ OK ] IPAM ipam-… state: create-complete
[ OK ] Pool ipam-pool-…: create-complete, CIDR provisioned
...
[ OK ] IPAM pools RAM share status: ACTIVE
```

A first apply takes 10-15 minutes (TGWs and peering are slow to become
`available`).

## Destroy behaviour

`terraform destroy` removes routes, peering, RAM shares, IPAM pools and
IPAM, Transit Gateways and the SSM contract, **but only if nothing depends
on them**: spoke VPC attachments on a TGW and VPC CIDRs allocated from a
pool both block deletion. The pre helper lists them on destroy. Detach the
spokes and release allocations (delete the spoke VPCs or re-address them)
first. Deprovisioning IPAM pool CIDRs can take several minutes per pool.

## References

- [Transit Gateway inter-region peering](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-peering.html)
- [Share a Transit Gateway with RAM](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-transit-gateways.html#tgw-sharing)
- [IPAM: integrate with AWS Organizations](https://docs.aws.amazon.com/vpc/latest/ipam/enable-integ-ipam.html), [share a pool with RAM](https://docs.aws.amazon.com/vpc/latest/ipam/share-pool-ipam.html), [tiers](https://docs.aws.amazon.com/vpc/latest/ipam/choose-ipam-tier.html)
- [AWS provider: per-resource region](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/enhanced-region-support)
