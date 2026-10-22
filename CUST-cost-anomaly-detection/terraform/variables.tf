variable "region" {
  description = "Provider region. Cost Explorer / Cost Anomaly Detection is a global service served from us-east-1; leave the default."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging."
  type        = string
  default     = "CUST-cost-anomaly-detection"
}

# ---- Alerting ----------------------------------------------------------------

variable "alert_email" {
  description = "Email address that receives cost anomaly alerts. CHANGE THIS before deploying."
  type        = string
  default     = "cost-alerts@example.com"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "alert_frequency" {
  description = "How often alerts are sent. Email subscribers support DAILY or WEEKLY (IMMEDIATE requires an SNS subscriber)."
  type        = string
  default     = "DAILY"

  validation {
    condition     = contains(["DAILY", "WEEKLY"], var.alert_frequency)
    error_message = "alert_frequency must be DAILY or WEEKLY for email subscribers."
  }
}

variable "alert_threshold_usd" {
  description = "Only alert on anomalies whose total cost impact is at least this many USD."
  type        = number
  default     = 100

  validation {
    condition     = var.alert_threshold_usd >= 0
    error_message = "alert_threshold_usd must be zero or greater."
  }
}

variable "monitor_name" {
  description = "Name of the AWS-services anomaly monitor. AWS allows one SERVICE-dimension monitor per account."
  type        = string
  default     = "platformr-aws-services-monitor"
}

variable "subscription_name" {
  description = "Name of the alert subscription."
  type        = string
  default     = "platformr-cost-anomaly-alerts"
}
