variable "alb_names" {
  description = "The name of the Application Load Balancer to associate the WAF with"
  type        = list(string)
}

variable "api_gateway_ids" {
  description = "The IDs of the API Gateway v2 instances to associate the WAF with"
  type        = list(string)
}

variable "cloudfront_distribution_ids" {
  description = "The IDs of the CloudFront distributions to associate the WAF with"
  type        = list(string)
}

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
}

variable "global" {
  description = "Boolean indicating if the WAF is for global (CloudFront) or regional resources"
  type        = bool
  default     = false
}

variable "protection_rules" {
  description = "Security protection rules configuration for the WAF"
  type = object({
    # Custom IP blocking rule
    ip_blocking = optional(object({
      enabled = optional(bool, false)
      action  = optional(string, "block") # block, count, or allow
      ips     = optional(list(string), [])
    }), {})

    # Custom path/endpoint blocking rule
    path_blocking = optional(object({
      enabled = optional(bool, false)
      action  = optional(string, "block") # block, count, or allow
      paths   = optional(list(string), [])
    }), {})

    # Protects against common web attacks
    basic_protection = optional(object({
      enabled = optional(bool, true)
      action  = optional(string, "block") # block, count, or allow
    }), {})

    # Blocks known malicious requests
    malicious_requests = optional(object({
      enabled = optional(bool, true)
      action  = optional(string, "block") # block, count, or allow
    }), {})

    # Protects against SQL injection attacks
    sql_injection = optional(object({
      enabled = optional(bool, true)
      action  = optional(string, "block") # block, count, or allow
    }), {})

    # Windows system specific protection
    windows_protection = optional(object({
      enabled = optional(bool, true)
      action  = optional(string, "block") # block, count, or allow
    }), {})

    # Linux system specific protection
    linux_protection = optional(object({
      enabled = optional(bool, true)
      action  = optional(string, "block") # block, count, or allow
    }), {})
  })
  default = {}
}

variable "disabled_rules" {
  description = "Specific AWS managed rules to disable if they cause false positives"
  type = object({
    basic_protection   = optional(list(string), [])
    malicious_requests = optional(list(string), [])
    sql_injection      = optional(list(string), [])
    windows_protection = optional(list(string), [])
    linux_protection   = optional(list(string), [])
  })
  default = {}
}

variable "waf_log_destination_arn" {
  description = "The ARN of the S3 bucket to store WAF logs"
  type        = string
}