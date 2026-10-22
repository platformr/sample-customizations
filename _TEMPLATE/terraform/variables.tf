variable "region" {
  description = "AWS region to deploy this customization into."
  type        = string
  default     = "us-east-1"
}

variable "customization_name" {
  description = "Name of this customization (the CUST-* directory name). Used for tagging."
  type        = string
  default     = "CUST-CHANGE-ME"
}
