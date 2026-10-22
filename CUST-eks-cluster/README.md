# CUST-eks-cluster

> A cost-conscious, production-shaped starter EKS cluster: its own VPC, EKS
> Auto Mode compute, Helm-installed defaults (StorageClass, IngressClass,
> metrics-server), and an SSM parameter contract so workloads can find and
> deploy to the cluster without touching this Terraform state.

## What it does

**Network** (`vpc.tf`): a new VPC (`10.42.0.0/16` by default) across 2 AZs
with public subnets for load balancers and private subnets for nodes, one
shared NAT gateway, and the `kubernetes.io/role/*` subnet tags the load
balancer controller needs.

**Cluster** (`main.tf`): an EKS cluster in **Auto Mode** with the
`general-purpose` and `system` node pools. AWS runs the nodes, VPC CNI,
CoreDNS, kube-proxy, EBS CSI, and the ALB/NLB controller. Secrets are
encrypted with a module-managed KMS key, the API endpoint is public but
CIDR-restrictable, auth is EKS access entries (API mode), and `api` +
`audit` control-plane logs go to CloudWatch with 14-day retention.

**Defaults via Helm** (`helm.tf` + `charts/`): the two things Auto Mode
leaves to you plus the usual first add-on:

| Release | Chart | Creates |
| --- | --- | --- |
| `cluster-defaults` | local `charts/cluster-defaults` | default **StorageClass `gp3`** (encrypted, `ebs.csi.eks.amazonaws.com`), **IngressClass `alb`** + `IngressClassParams` (internet-facing) |
| `metrics-server` | kubernetes-sigs upstream | metrics-server for `kubectl top` and HPA |

**Contract** (`ssm.tf`): every value a workload deployment needs is
published under `/platformr/CUST-eks-cluster/` (see below).

## Why these choices (cost and best practice)

| Choice | Reason |
| --- | --- |
| Auto Mode | No node groups, Karpenter or add-ons to operate; nodes scale to **zero** when idle, so an empty cluster costs control plane + NAT + KMS only. Trade-off: a management fee on EC2 usage; large steady fleets may prefer managed node groups. |
| 2 AZs, single NAT | Minimum for an HA control plane; one NAT (~USD 32/mo) instead of two or three. `availability_zone_count = 3` and `single_nat_gateway = false` for production HA. |
| `kubernetes_version = null` | Uses the current EKS default, which is always in standard support (no extended-support surcharge). Pin it once you have workloads. |
| `api` + `audit` logs, 14 days | Security-relevant logs without paying for scheduler/controller chatter. |
| Private nodes, public LBs | Nodes never get public IPs. |
| Access entries, not `aws-auth` | The modern, auditable auth path. The deploy identity gets admin; add others via `cluster_admin_principal_arns`. |
| KMS secrets encryption | Default-on best practice; ~USD 1/mo. |

Rough idle cost in us-east-1: control plane USD 73/mo + NAT USD 32/mo +
KMS USD 1/mo. Nodes bill only while pods are scheduled.

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/vpc.tf` | `terraform-aws-modules/vpc/aws` ~> 6.0 |
| `terraform/main.tf` | `terraform-aws-modules/eks/aws` ~> 21.0 in Auto Mode, access entries |
| `terraform/helm.tf`, `terraform/charts/` | `helm_release` for cluster-defaults (local chart) and metrics-server |
| `terraform/ssm.tf` | The SSM parameter contract |
| `api_helpers/pre-api-helpers.sh` | apply: AZ count, existing-cluster report. destroy: warns about LBs/volumes created by workloads that would block VPC deletion |
| `api_helpers/post-api-helpers.sh` | Cluster ACTIVE + Auto Mode, all SSM parameters present, and (if `kubectl` is on the build image) StorageClass/IngressClass/metrics-server exist |

The Helm provider authenticates with `aws eks get-token`, so the build image
needs the AWS CLI (it does) and network reach to the API endpoint.

## SSM parameters (the contract for workloads)

All parameters live under **`/platformr/CUST-eks-cluster/`**. Workload
customizations or pipelines read them with `data "aws_ssm_parameter"` or
`aws ssm get-parameter` and never need this Terraform state.

| Parameter | Type | Example / meaning |
| --- | --- | --- |
| `cluster_name` | String | `platformr-eks` |
| `cluster_arn` | String | `arn:aws:eks:us-east-1:123456789012:cluster/platformr-eks` |
| `cluster_endpoint` | String | `https://ABC...gr7.us-east-1.eks.amazonaws.com` |
| `cluster_certificate_authority_data` | String | base64 CA bundle for kubeconfig / providers |
| `cluster_version` | String | `1.33` |
| `cluster_security_group_id` | String | Cluster security group (control plane ENIs) |
| `node_security_group_id` | String | Node security group; add rules here to reach nodes |
| `oidc_provider_arn` | String | IAM OIDC provider ARN, for IRSA trust policies |
| `oidc_issuer_url` | String | OIDC issuer URL, for IRSA trust conditions |
| `node_iam_role_arn` | String | Auto Mode node role (grant ECR/S3 access here if needed) |
| `vpc_id` | String | `vpc-0abc...` |
| `vpc_cidr` | String | `10.42.0.0/16` |
| `private_subnet_ids` | StringList | comma-separated; nodes and internal LBs |
| `public_subnet_ids` | StringList | comma-separated; internet-facing LBs |
| `availability_zones` | StringList | comma-separated AZ names in subnet order |
| `region` | String | `us-east-1` |
| `default_storage_class` | String | `gp3` (use in PVCs, or omit to get the default) |
| `ingress_class_name` | String | `alb` (use in `spec.ingressClassName`, or omit) |
| `ingress_scheme` | String | `internet-facing` |
| `kubeconfig_command` | String | `aws eks update-kubeconfig --name platformr-eks --region us-east-1` |

### Consuming the contract from another customization

```hcl
data "aws_ssm_parameter" "cluster_name" {
  name = "/platformr/CUST-eks-cluster/cluster_name"
}

data "aws_ssm_parameter" "cluster_endpoint" {
  name = "/platformr/CUST-eks-cluster/cluster_endpoint"
}

data "aws_ssm_parameter" "cluster_ca" {
  name = "/platformr/CUST-eks-cluster/cluster_certificate_authority_data"
}

data "aws_ssm_parameter" "private_subnets" {
  name = "/platformr/CUST-eks-cluster/private_subnet_ids"
}

locals {
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnets.value)
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_ssm_parameter.cluster_endpoint.value
    cluster_ca_certificate = base64decode(data.aws_ssm_parameter.cluster_ca.value)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.aws_ssm_parameter.cluster_name.value]
    }
  }
}
```

From a shell or pipeline:

```bash
eval "$(aws ssm get-parameter --name /platformr/CUST-eks-cluster/kubeconfig_command --query Parameter.Value --output text)"
kubectl get nodes
```

Note the repository rule: customizations must not depend on each other at
*deploy* time. A workload customization that reads these parameters must
tolerate their absence (fail with a clear message in its pre helper) rather
than assume `CUST-eks-cluster` ran first.

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | |
| `cluster_name` | `platformr-eks` | Cluster and VPC name. |
| `kubernetes_version` | `null` | `null` = current EKS default. |
| `endpoint_public_access` | `true` | Public API endpoint (needed unless the build runner is inside the VPC). |
| `endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | **Narrow this.** |
| `cluster_admin_principal_arns` | `[]` | Extra cluster-admin principals via access entries. |
| `control_plane_log_types` | `["api","audit"]` | |
| `control_plane_log_retention_days` | `14` | |
| `auto_mode_node_pools` | `["general-purpose","system"]` | |
| `vpc_cidr` | `10.42.0.0/16` | |
| `availability_zone_count` | `2` | 2 or 3. |
| `single_nat_gateway` | `true` | `false` = one NAT per AZ. |
| `install_metrics_server` | `true` | |
| `metrics_server_chart_version` | `3.12.2` | |
| `default_storage_class_name` | `gp3` | |
| `ingress_class_name` | `alb` | |
| `ingress_scheme` | `internet-facing` | or `internal`. |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `CUSTOMIZATION_NAME` | `CUST-eks-cluster` | SSM path prefix. |
| `CLUSTER_NAME` | from SSM / `platformr-eks` | Used on destroy when SSM is already gone. |

## Permissions required by the deployment role

Broad by nature (VPC, EKS, IAM roles for the cluster and nodes, KMS, logs,
SSM). Start from these managed policies for the deployment role and narrow
once stable:

```
AmazonEKSClusterPolicy-level actions: eks:*  (cluster, access entries, add-ons)
ec2:*Vpc*, ec2:*Subnet*, ec2:*RouteTable*, ec2:*InternetGateway*, ec2:*NatGateway*,
ec2:*Address*, ec2:*SecurityGroup*, ec2:Describe*, ec2:CreateTags, ec2:DeleteTags
iam:CreateRole, iam:DeleteRole, iam:GetRole, iam:PassRole, iam:*RolePolicy*,
iam:AttachRolePolicy, iam:DetachRolePolicy, iam:TagRole, iam:CreateOpenIDConnectProvider,
iam:DeleteOpenIDConnectProvider, iam:GetOpenIDConnectProvider, iam:TagOpenIDConnectProvider,
iam:CreateServiceLinkedRole
kms:CreateKey, kms:DescribeKey, kms:*Alias*, kms:PutKeyPolicy, kms:ScheduleKeyDeletion,
kms:TagResource, kms:EnableKeyRotation, kms:GetKeyPolicy, kms:ListResourceTags
logs:CreateLogGroup, logs:DeleteLogGroup, logs:PutRetentionPolicy, logs:DescribeLogGroups,
logs:TagResource, logs:ListTagsForResource
ssm:PutParameter, ssm:GetParameter, ssm:DeleteParameter, ssm:AddTagsToResource,
ssm:ListTagsForResource
elasticloadbalancing:DescribeLoadBalancers   (pre-destroy check)
```

## Validation

```
[ OK ] Cluster name: platformr-eks
[ OK ] Cluster status: ACTIVE
[ OK ] Auto Mode compute enabled: True
[ OK ] Kubernetes version: 1.33
[ OK ] SSM cluster_name: platformr-eks
[ OK ] SSM cluster_endpoint: https://...
...
[ OK ] StorageClass gp3: gp3
[ OK ] IngressClass alb: alb
[ OK ] metrics-server ready replicas: 1
```

A fresh apply takes 15-20 minutes (control plane ~10 min, then Helm).

## Destroy behaviour

`terraform destroy` removes the Helm releases, cluster, KMS key (30-day
pending deletion), log group, SSM parameters, NAT gateway and VPC.

**Anything Kubernetes created on your behalf is not in this state**: ALBs
and NLBs from Ingress/Service objects, EBS volumes from PVCs. Load balancers
block VPC deletion; volumes are orphaned and keep billing. The pre helper
lists both on destroy. Delete the workloads (or at least their Ingress,
Service type LoadBalancer and PVC objects) before destroying the cluster.

## References

- [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [EKS Auto Mode: create a StorageClass](https://docs.aws.amazon.com/eks/latest/userguide/create-storage-class.html) and [IngressClass](https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-alb.html)
- [EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [terraform-aws-modules/eks](https://github.com/terraform-aws-modules/terraform-aws-eks), [terraform-aws-modules/vpc](https://github.com/terraform-aws-modules/terraform-aws-vpc)
- [Helm provider v3](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
