variable "region" {
  description = "Home region: hosts the IPAM, the IPAM RAM share (RAM for IPAM pools only works in the IPAM home region) and the SSM contract. Must be one of the hub regions or an extra operating region."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging and the SSM parameter prefix."
  type        = string
  default     = "CUST-transitive-network-hub-account"
}

variable "name_prefix" {
  description = "Prefix for resource names and Name tags."
  type        = string
  default     = "network-hub"
}

# ---- Regions -----------------------------------------------------------------

variable "hub_regions" {
  description = <<-EOT
    ONE or TWO regions that get a Transit Gateway, a regional IPAM pool and
    per-environment sub-pools. Each entry needs a unique private ASN for the
    TGW and the summary CIDR for the region, carved from var.cloud_cidr. With
    two regions the Transit Gateways are peered. For a single region, keep
    just one entry.
  EOT
  type = map(object({
    asn  = number
    cidr = string
  }))
  default = {
    "us-east-1" = { asn = 64512, cidr = "172.16.0.0/13" }
    "us-west-2" = { asn = 64513, cidr = "172.24.0.0/13" }
  }

  validation {
    condition     = length(var.hub_regions) >= 1 && length(var.hub_regions) <= 2
    error_message = "hub_regions must contain one or two regions (raise this limit deliberately if you need more; every extra region adds a TGW, pools and peering)."
  }

  validation {
    condition     = length(distinct([for r in var.hub_regions : r.asn])) == length(var.hub_regions)
    error_message = "Each hub region needs a unique Transit Gateway ASN."
  }

  validation {
    condition = alltrue([
      for r in var.hub_regions :
      (r.asn >= 64512 && r.asn <= 65534) || (r.asn >= 4200000000 && r.asn <= 4294967294)
    ])
    error_message = "Transit Gateway ASNs must be private: 64512-65534 or 4200000000-4294967294."
  }

  validation {
    condition     = alltrue([for r in var.hub_regions : can(cidrhost(r.cidr, 0))])
    error_message = "Each hub region cidr must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = length(distinct([for r in var.hub_regions : r.cidr])) == length(var.hub_regions)
    error_message = "Hub region CIDRs must not repeat."
  }
}

# ---- IP plan -----------------------------------------------------------------

variable "cloud_cidr" {
  description = "Top-level private CIDR for the whole cloud estate. Region CIDRs in hub_regions must sit inside it. Must not overlap on-premises ranges."
  type        = string
  default     = "172.16.0.0/12"

  validation {
    condition     = can(cidrhost(var.cloud_cidr, 0))
    error_message = "cloud_cidr must be a valid IPv4 CIDR block."
  }
}

variable "environments" {
  description = "Environment sub-pools carved equally from each region's CIDR, in this order. 4 environments in a /13 region gives /15 per environment."
  type        = list(string)
  default     = ["production", "development", "management", "shared-services"]

  validation {
    condition     = length(var.environments) >= 1 && length(var.environments) == length(distinct(var.environments))
    error_message = "environments must be a non-empty list of unique names."
  }

  validation {
    condition     = alltrue([for e in var.environments : can(regex("^[a-z0-9][a-z0-9-]*$", e))])
    error_message = "environment names must be lowercase letters, digits and dashes."
  }
}

variable "vpc_allocation_netmask" {
  description = "Default, minimum and maximum prefix length a spoke may allocate from an environment pool (e.g. a VPC request without a size gets a /20)."
  type = object({
    default = number
    min     = number
    max     = number
  })
  default = {
    default = 20
    min     = 16
    max     = 28
  }

  validation {
    condition     = var.vpc_allocation_netmask.min <= var.vpc_allocation_netmask.default && var.vpc_allocation_netmask.default <= var.vpc_allocation_netmask.max
    error_message = "vpc_allocation_netmask must satisfy min <= default <= max."
  }
}

variable "ipam_tier" {
  description = "IPAM tier. Sharing pools across the organization requires Organizations integration, which needs the advanced tier (billed per active IP address). free works for a single-account lab only."
  type        = string
  default     = "advanced"

  validation {
    condition     = contains(["free", "advanced"], var.ipam_tier)
    error_message = "ipam_tier must be free or advanced."
  }
}

# ---- Sharing -----------------------------------------------------------------

variable "ram_principals" {
  description = "Principals to share the Transit Gateways and IPAM pools with (organization ARN, OU ARNs or account IDs). Empty = the whole organization this account belongs to."
  type        = list(string)
  default     = []
}

variable "enable_transit_gateway_peering" {
  description = "Create full-mesh inter-region peering between the hub Transit Gateways with static summary routes."
  type        = bool
  default     = true
}
