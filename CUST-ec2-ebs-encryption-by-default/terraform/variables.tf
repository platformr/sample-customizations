variable "region" {
  description = "Region to enable EBS encryption by default in. This is a per-region setting; deploy once per region."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging."
  type        = string
  default     = "CUST-ec2-ebs-encryption-by-default"
}

variable "default_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN to use as the region's default EBS encryption key. Null keeps the AWS managed key (alias aws/ebs)."
  type        = string
  default     = null

  validation {
    condition     = var.default_kms_key_arn == null || can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/", var.default_kms_key_arn))
    error_message = "default_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>) or null."
  }
}
