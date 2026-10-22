variable "region" {
  description = "Provider region for the SSM marker parameters. The helpers themselves sweep every enabled region regardless of this value."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging and the SSM parameter prefix."
  type        = string
  default     = "CUST-delete-default-vpcs"
}
