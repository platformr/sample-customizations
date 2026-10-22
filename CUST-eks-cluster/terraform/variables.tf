variable "region" {
  description = "Region to deploy the VPC and EKS cluster into."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging and the SSM parameter prefix."
  type        = string
  default     = "CUST-eks-cluster"
}

# ---- Cluster -----------------------------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name. Also used as the VPC name and in SSM parameter values."
  type        = string
  default     = "platformr-eks"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be 1-100 characters: letters, digits, dashes, underscores."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes <major>.<minor> version (e.g. \"1.33\"). Null lets EKS pick its current default, which is the newest standard-support version (no extended-support surcharge)."
  type        = string
  default     = null
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint publicly (restricted by endpoint_public_access_cidrs). Private access is always on. The Helm provider in this customization needs to reach the endpoint from the build environment."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Narrow this to your office/VPN/CI egress ranges."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_admin_principal_arns" {
  description = "IAM principal ARNs (roles/users) to grant cluster-admin via EKS access entries, in addition to the identity running Terraform."
  type        = list(string)
  default     = []
}

variable "control_plane_log_types" {
  description = "Control-plane log types to ship to CloudWatch. api+audit covers security needs; add authenticator, controllerManager, scheduler when debugging."
  type        = list(string)
  default     = ["api", "audit"]
}

variable "control_plane_log_retention_days" {
  description = "Retention for the control-plane log group."
  type        = number
  default     = 14
}

variable "auto_mode_node_pools" {
  description = "EKS Auto Mode built-in node pools to enable. general-purpose (on-demand, amd64) and system (for cluster add-ons)."
  type        = list(string)
  default     = ["general-purpose", "system"]

  validation {
    condition     = alltrue([for p in var.auto_mode_node_pools : contains(["general-purpose", "system"], p)])
    error_message = "auto_mode_node_pools may only contain general-purpose and/or system."
  }
}

# ---- VPC ---------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR for the new VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of AZs to spread subnets across. 2 is the cost-effective minimum for an HA control plane; 3 for production."
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zone_count >= 2 && var.availability_zone_count <= 3
    error_message = "availability_zone_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all private subnets (cheapest). Set false for one per AZ (HA egress, ~3x NAT cost)."
  type        = bool
  default     = true
}

# ---- Helm-installed defaults -------------------------------------------------

variable "install_metrics_server" {
  description = "Install metrics-server via Helm (needed for kubectl top and HorizontalPodAutoscaler)."
  type        = bool
  default     = true
}

variable "metrics_server_chart_version" {
  description = "metrics-server Helm chart version."
  type        = string
  default     = "3.12.2"
}

variable "default_storage_class_name" {
  description = "Name of the default StorageClass created for EBS gp3 volumes (EKS Auto Mode EBS CSI)."
  type        = string
  default     = "gp3"
}

variable "ingress_class_name" {
  description = "Name of the default IngressClass backed by the EKS Auto Mode ALB controller."
  type        = string
  default     = "alb"
}

variable "ingress_scheme" {
  description = "Scheme for ALBs created through the default IngressClass: internet-facing or internal."
  type        = string
  default     = "internet-facing"

  validation {
    condition     = contains(["internet-facing", "internal"], var.ingress_scheme)
    error_message = "ingress_scheme must be internet-facing or internal."
  }
}
