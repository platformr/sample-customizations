# ------------------------------------------------------------------------------
# VPC for the cluster
#
# Cost-conscious layout: 2 AZs by default, public subnets for load balancers,
# private subnets for nodes, one shared NAT gateway. Subnet tags let the EKS
# Auto Mode load balancer controller discover where to place ALBs/NLBs.
# ------------------------------------------------------------------------------

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.availability_zone_count)

  # /20 private subnets (4094 IPs each, room for pods), /24 public subnets.
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Nodes never get public IPs; only load balancers live in public subnets.
  map_public_ip_on_launch = false

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
