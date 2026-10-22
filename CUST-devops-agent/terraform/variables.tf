variable "region" {
  description = "Region to create the DevOps Agent agent space in. Must be one of the regions where AWS DevOps Agent is available."
  type        = string
  default     = "us-east-1"

  validation {
    condition = contains([
      "us-east-1",      # US East (N. Virginia)
      "us-west-2",      # US West (Oregon)
      "eu-central-1",   # Europe (Frankfurt)
      "eu-west-1",      # Europe (Ireland)
      "ap-southeast-2", # Asia Pacific (Sydney)
      "ap-northeast-1", # Asia Pacific (Tokyo)
    ], var.region)
    error_message = "AWS DevOps Agent is only available in us-east-1, us-west-2, eu-central-1, eu-west-1, ap-southeast-2 and ap-northeast-1."
  }
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging and SSM parameter paths."
  type        = string
  default     = "CUST-devops-agent"
}

variable "agent_space_name" {
  description = "Name of the DevOps Agent agent space. post-api-helpers.sh looks the space up by the SSM parameter, not by this name, so renaming is safe."
  type        = string
  default     = "platformr-account-agent-space"
}

variable "agent_space_description" {
  description = "Description shown on the agent space."
  type        = string
  default     = "Account-level AWS DevOps Agent space managed by Platformr Customizations."
}

variable "agent_space_locale" {
  description = "Locale for agent responses (e.g. en). Null leaves the service default."
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for the agent space. The key policy must allow aidevops.amazonaws.com; see the DevOps Agent encryption docs. Forces replacement if changed."
  type        = string
  default     = null
}

variable "agent_space_role_name" {
  description = "IAM role the agent space assumes to discover and inspect resources in this account."
  type        = string
  default     = "DevOpsAgentRole-AgentSpace"
}

variable "operator_app_role_name" {
  description = "IAM role the operator web app assumes (IAM auth flow)."
  type        = string
  default     = "DevOpsAgentRole-WebappAdmin"
}
