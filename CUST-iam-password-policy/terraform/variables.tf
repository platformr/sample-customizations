variable "region" {
  description = "Provider region. IAM is global; the password policy applies to the whole account regardless of this value."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging."
  type        = string
  default     = "CUST-iam-password-policy"
}

# ---- Policy values -----------------------------------------------------------
# Defaults match the AWS Config managed rule IAM_PASSWORD_POLICY defaults, which
# in turn reflect the CIS AWS Foundations Benchmark controls for IAM password
# policy (minimum length 14, reuse prevention 24, all four character classes).

variable "minimum_password_length" {
  description = "Minimum password length. CIS requires 14 or more."
  type        = number
  default     = 14

  validation {
    condition     = var.minimum_password_length >= 14 && var.minimum_password_length <= 128
    error_message = "minimum_password_length must be between 14 (CIS minimum) and 128."
  }
}

variable "password_reuse_prevention" {
  description = "Number of previous passwords a user cannot reuse. CIS requires 24."
  type        = number
  default     = 24

  validation {
    condition     = var.password_reuse_prevention >= 1 && var.password_reuse_prevention <= 24
    error_message = "password_reuse_prevention must be between 1 and 24."
  }
}

variable "max_password_age" {
  description = "Days before a password expires. Config rule default is 90."
  type        = number
  default     = 90

  validation {
    condition     = var.max_password_age >= 1 && var.max_password_age <= 1095
    error_message = "max_password_age must be between 1 and 1095 days."
  }
}

variable "require_uppercase_characters" {
  description = "Require at least one uppercase character."
  type        = bool
  default     = true
}

variable "require_lowercase_characters" {
  description = "Require at least one lowercase character."
  type        = bool
  default     = true
}

variable "require_numbers" {
  description = "Require at least one number."
  type        = bool
  default     = true
}

variable "require_symbols" {
  description = "Require at least one non-alphanumeric character."
  type        = bool
  default     = true
}

variable "allow_users_to_change_password" {
  description = "Allow IAM users to change their own password."
  type        = bool
  default     = true
}

variable "hard_expiry" {
  description = "If true, users whose password has expired cannot set a new one and need an administrator reset."
  type        = bool
  default     = false
}
