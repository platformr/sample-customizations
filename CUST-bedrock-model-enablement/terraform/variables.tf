variable "region" {
  description = "Region to create the model agreements in. Agreements are account-level, but the API is regional; us-east-1 is used for the example."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging and SSM parameter paths."
  type        = string
  default     = "CUST-bedrock-model-enablement"
}

# ---- Models ------------------------------------------------------------------

variable "model_ids" {
  description = <<-EOT
    Base Bedrock model IDs to create foundation-model agreements for. Use the
    bare model ID from the model card (not the us./global. inference profile
    ID). Defaults to Anthropic Claude Fable 5.1 and Claude Opus 5.5.
  EOT
  type        = list(string)
  default = [
    "anthropic.claude-fable-5-1",
    "anthropic.claude-opus-5-5",
  ]

  validation {
    condition     = length(var.model_ids) > 0 && alltrue([for m in var.model_ids : can(regex("^[a-z0-9-]+\\.[A-Za-z0-9.:-]+$", m))])
    error_message = "model_ids must be non-empty base model IDs like anthropic.claude-opus-5-5 (no us./global. prefix)."
  }
}

# ---- Anthropic first-time use-case form --------------------------------------
# Required once per account (or once at the Organizations management account,
# which child accounts inherit) before any Anthropic model can be invoked.

variable "submit_use_case_form" {
  description = "Submit the Anthropic first-time use-case form. Set false if the organization's management account already submitted it."
  type        = bool
  default     = true
}

variable "use_case_company_name" {
  description = "Company name for the use-case form (max 128 chars)."
  type        = string
  default     = "Example Corp"
}

variable "use_case_company_website" {
  description = "Company website for the use-case form (max 128 chars)."
  type        = string
  default     = "https://www.example.com"
}

variable "use_case_intended_users" {
  description = "Who uses the models: 0 = internal, 1 = external, 2 = internal and external."
  type        = string
  default     = "0"

  validation {
    condition     = contains(["0", "1", "2"], var.use_case_intended_users)
    error_message = "use_case_intended_users must be \"0\", \"1\" or \"2\"."
  }
}

variable "use_case_industry" {
  description = "Industry for the use-case form (e.g. Technology, Financial Services, Healthcare)."
  type        = string
  default     = "Technology"
}

variable "use_case_description" {
  description = "Description of intended use cases (max 8192 chars)."
  type        = string
  default     = "- Internal developer tooling and code assistance\n- Document summarization and knowledge retrieval\n- Internal chat assistants"
}

# ---- Data retention (required for Claude Fable 5 / 5.1) ----------------------

variable "data_retention_mode" {
  description = <<-EOT
    Account-level Bedrock data retention mode to set in var.region via
    PutAccountDataRetention (applied by post-api-helpers.sh; no Terraform
    resource exists). Claude Fable 5 and 5.1 are only invokable when the
    effective mode is "aws_review" (inputs/outputs retained up to 30 days
    for AWS human review, never shared with the model provider). Set to null
    to leave the account's current setting untouched.
    Valid: none | default | aws_review | null.
  EOT
  type        = string
  default     = "aws_review"

  validation {
    condition     = var.data_retention_mode == null || contains(["none", "default", "aws_review"], var.data_retention_mode)
    error_message = "data_retention_mode must be none, default, aws_review or null."
  }
}
