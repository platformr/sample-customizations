# ------------------------------------------------------------------------------
# EKS cluster (Auto Mode)
#
# Why Auto Mode for a starter cluster:
#   * No node groups, Karpenter, CNI/CoreDNS/kube-proxy/EBS-CSI/ALB add-ons to
#     install or upgrade; AWS runs them.
#   * Nodes scale to ZERO when nothing is scheduled, so an idle cluster costs
#     only the control plane (~USD 0.10/h) + NAT gateway + KMS key.
#   * Trade-off: an Auto Mode management fee on EC2 usage. For large, steady
#     fleets managed node groups can be cheaper; swap `compute_config` for
#     `eks_managed_node_groups` in that case.
#
# Other cost/security choices: 2 AZs, single NAT, api+audit logs only with
# short retention, secrets encrypted with a module-managed KMS key, private
# nodes, access via EKS access entries (API auth) instead of aws-auth.
# ------------------------------------------------------------------------------

locals {
  partition = data.aws_partition.current.partition

  cluster_admin_policy_arn = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_entries = {
    for arn in var.cluster_admin_principal_arns : arn => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = local.cluster_admin_policy_arn
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # EKS Auto Mode: AWS-managed compute, networking, storage and load balancing.
  compute_config = {
    enabled    = true
    node_pools = var.auto_mode_node_pools
  }

  # Auth: API access entries. The Terraform identity (the Platformr deployment
  # role) is made cluster-admin so the Helm provider can install defaults.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  access_entries                           = local.access_entries

  # Observability (kept lean on purpose).
  enabled_log_types                      = var.control_plane_log_types
  cloudwatch_log_group_retention_in_days = var.control_plane_log_retention_days

  # Secrets encryption with a module-managed KMS key (default: create_kms_key = true).
  kms_key_enable_default_policy = true

  tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}
