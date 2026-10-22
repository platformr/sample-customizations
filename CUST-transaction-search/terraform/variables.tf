variable "region" {
  description = "AWS region to enable Transaction Search in. Transaction Search is a per-region, account-level setting."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging."
  type        = string
  default     = "CUST-transaction-search"
}

variable "indexing_percentage" {
  description = "Percentage of ingested spans to index as trace summaries. 1% is free; higher values incur X-Ray trace indexing charges."
  type        = number
  default     = 1

  validation {
    condition     = var.indexing_percentage >= 0 && var.indexing_percentage <= 100
    error_message = "indexing_percentage must be between 0 and 100."
  }
}

variable "logs_resource_policy_name" {
  description = "Name of the account-level CloudWatch Logs resource policy that lets X-Ray write spans. Accounts are limited to 10 such policies per region."
  type        = string
  default     = "TransactionSearchAccess"
}

variable "agentcore_log_delivery" {
  description = <<-EOT
    OPTIONAL. Map of Bedrock AgentCore memory/gateway resources to configure vended
    log and trace delivery for. Key is a short id used in log-group and delivery
    names; value is the AgentCore resource ARN. Leave empty if agents are not
    deployed yet; the delivery can be added later by any workload stack.

    Example:
      {
        "my-memory-id" = "arn:aws:bedrock-agentcore:us-east-1:<ACCOUNT_ID>:memory/my-memory-id"
      }
  EOT
  type        = map(string)
  default     = {}
}

variable "agentcore_log_retention_days" {
  description = "Retention for the vended AgentCore log groups created from agentcore_log_delivery."
  type        = number
  default     = 30
}
