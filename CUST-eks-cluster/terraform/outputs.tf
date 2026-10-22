output "account_id" {
  description = "Account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Region the cluster was created in."
  value       = data.aws_region.current.region
}

output "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn)."
  value       = data.aws_partition.current.partition
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster."
  value       = module.eks.cluster_version
}

output "vpc_id" {
  description = "VPC created for the cluster."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets (nodes, internal load balancers)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnets (internet-facing load balancers)."
  value       = module.vpc.public_subnets
}

output "ssm_parameter_prefix" {
  description = "SSM path under which the cluster contract is published."
  value       = local.ssm_prefix
}

output "ssm_parameter_names" {
  description = "All SSM parameter names published for workloads."
  value       = sort(concat([for p in aws_ssm_parameter.string : p.name], [for p in aws_ssm_parameter.list : p.name]))
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for this cluster."
  value       = local.ssm_strings.kubeconfig_command
}
