provider "aws" {
  region = var.region

  default_tags {
    tags = {
      managed_by    = "platformr_Customizations"
      customization = var.customization_name
    }
  }
}

# Helm talks to the cluster with a short-lived token from the AWS CLI on the
# build image (the same credentials Terraform uses). Requires the public API
# endpoint to be reachable from the build environment, or a build runner
# inside the VPC when var.endpoint_public_access is false.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
