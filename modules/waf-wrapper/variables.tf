variable "alb_names" {
  description = "List of ALB names to associate with the WAF Web ACL"
  type        = list(string)
  default     = []
}

variable "api_gateway_ids" {
  description = "List of API Gateway v2 IDs to associate with the WAF Web ACL"
  type        = list(string)
}

variable "cloudfront_distribution_ids" {
  description = "List of CloudFront distribution IDs to associate with the WAF Web ACL"
  type        = list(string)
}

variable "environment" {
  description = "Name of the environment (e.g., prod-us-east-1, prod-global)"
  type        = string
}

variable "firehose_destination" {
  description = "ARN of the Firehose delivery stream for WAF logs"
  type        = string
}

variable "firehose_role_arn" {
  description = "ARN of the IAM role used by Firehose"
  type        = string
}

variable "global" {
  description = "Boolean indicating if the WAF is for global (CloudFront) or regional resources"
  type        = bool
  default     = false
}

variable "log_forward_destination" {
  description = "ARN of the log destination for WAF logs"
  type        = string
  default     = ""
}


variable "protection_rules" {
  description = "Security protection rules configuration for the WAF"
  type = object({
    # Custom IP blocking rule
    ip_blocking = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
      ips     = optional(list(string), [])
    }),

    # Custom path/endpoint blocking rule
    path_blocking = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
      paths   = optional(list(string), [])
    }),

    # Custom rate limiting rules
    rate_limiting = object({
      enabled = bool
      rules = list(object({
        name                  = string
        action                = string 
        limit                 = number
        aggregate_key_type    = string # IP, FORWARDED_IP, or AUTHENTICATED_USER
        evaluation_window_sec = number
        uri_path = optional(object({
          positional_constraint = string
          search_string         = string
        }))
        method = optional(string)
        header = optional(object({
          name                  = string
          positional_constraint = string
          search_string         = string
        }))
      }))
    })

    # Provides a CAPTCHA for public pages
    captcha = object({
      enabled = bool
      rules = list(object({
        name = string
        uri_path = optional(object({
          positional_constraint = string
          search_string         = string
        }))
        header = optional(object({
          name                  = string
          positional_constraint = string
          search_string         = string
        }))
      }))
    })

    # Protects against common web attacks
    basic_protection = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
    })

    # Blocks known malicious requests
    malicious_requests = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
    }),

    # Protects against SQL injection attacks
    sql_injection = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
    }),

    # Windows system specific protection
    windows_protection = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
    }),

    # Linux system specific protection
    linux_protection = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
    }),
  })
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

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}