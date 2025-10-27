variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
}

variable "log_forward_destination" {
  description = "ARN of the log destination for WAF logs"
  type        = string
  default     = ""
}