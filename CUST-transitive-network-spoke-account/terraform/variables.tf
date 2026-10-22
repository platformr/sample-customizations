variable "region" {
  description = "Home region for this customization's SSM contract. Spoke VPCs are created in var.spoke_regions regardless of this value."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging and the SSM parameter prefix."
  type        = string
  default     = "CUST-transitive-network-spoke-account"
}

variable "name_prefix" {
  description = "Prefix for resource names and Name tags in this account."
  type        = string
  default     = "spoke"
}

# ---- Where to build -----------------------------------------------------------

variable "spoke_regions" {
  description = "ONE or TWO regions to create a spoke VPC in. Each must be a hub region (the hub customization's hub_regions)."
  type        = list(string)
  default     = ["us-east-1"]

  validation {
    condition     = length(var.spoke_regions) >= 1 && length(var.spoke_regions) <= 2 && length(distinct(var.spoke_regions)) == length(var.spoke_regions)
    error_message = "spoke_regions must list one or two distinct regions."
  }
}

variable "environment" {
  description = "Hub environment pool to allocate from (one of the hub's environments, e.g. production, development, management, shared-services)."
  type        = string
  default     = "development"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and dashes."
  }
}

# ---- Hub discovery contract (must match CUST-transitive-network-hub-account) --

variable "hub_name_prefix" {
  description = "The hub's name_prefix. Drives the RAM share names (<prefix>-tgw-<region>) and IPAM pool descriptions (<prefix>: <region> <environment>) used for discovery."
  type        = string
  default     = "network-hub"
}

variable "hub_home_region" {
  description = "The hub's home region (its var.region): where the IPAM lives and where shared pools are visible."
  type        = string
  default     = "us-east-1"
}

variable "cloud_cidr" {
  description = "The hub's cloud_cidr. Routed from every spoke subnet to the Transit Gateway."
  type        = string
  default     = "172.16.0.0/12"

  validation {
    condition     = can(cidrhost(var.cloud_cidr, 0))
    error_message = "cloud_cidr must be a valid IPv4 CIDR block."
  }
}

# ---- VPC shape ------------------------------------------------------------------

variable "vpc_netmask_length" {
  description = "Prefix length to allocate from the environment pool for each VPC (within the pool's min/max). 16-20 so that /22 workload subnets and /28 transit subnets fit."
  type        = number
  default     = 20

  validation {
    condition     = var.vpc_netmask_length >= 16 && var.vpc_netmask_length <= 20
    error_message = "vpc_netmask_length must be between 16 and 20."
  }
}

variable "availability_zone_count" {
  description = "AZs per VPC (1-3). Each AZ gets a private workload subnet and a small transit subnet."
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zone_count >= 1 && var.availability_zone_count <= 3
    error_message = "availability_zone_count must be 1, 2 or 3."
  }
}

variable "route_default_via_transit_gateway" {
  description = "Also send 0.0.0.0/0 from the private subnets to the Transit Gateway (for centralised egress/inspection in the hub). Leave false if the hub has no egress path yet."
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames on the spoke VPCs."
  type        = bool
  default     = true
}
