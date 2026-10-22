variable "region" {
  description = "Region to set the IMDS account defaults in. This is a per-region setting; deploy once per region."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging and SSM parameter paths."
  type        = string
  default     = "CUST-enforce-imdsv2-on-account"
}

variable "http_put_response_hop_limit" {
  description = "Default IMDS hop limit for new instances. AWS recommends 2 when instances host containers; -1 means no preference (1, or 2 for AMIs with ImdsSupport v2.0)."
  type        = number
  default     = 2

  validation {
    condition     = var.http_put_response_hop_limit == -1 || (var.http_put_response_hop_limit >= 1 && var.http_put_response_hop_limit <= 64)
    error_message = "http_put_response_hop_limit must be -1 or between 1 and 64."
  }
}

variable "instance_metadata_tags" {
  description = "Account default for exposing instance tags via IMDS: enabled, disabled or no-preference."
  type        = string
  default     = "no-preference"

  validation {
    condition     = contains(["enabled", "disabled", "no-preference"], var.instance_metadata_tags)
    error_message = "instance_metadata_tags must be enabled, disabled or no-preference."
  }
}

variable "enforce" {
  description = "Also turn on account-level IMDSv2 ENFORCEMENT (HttpTokensEnforced=enabled): launches that try to allow IMDSv1 fail. Applied by post-api-helpers.sh because the provider does not expose this flag yet."
  type        = bool
  default     = true
}
