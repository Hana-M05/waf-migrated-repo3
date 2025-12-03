variable "alb_names" {
  description = "The name of the Application Load Balancer to associate the WAF with"
  type        = list(string)
}

variable "api_gateway_ids" {
  description = "The IDs of the API Gateway v2 instances to associate the WAF with"
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

    # Block Tenable scanner IPs
    block_unauthorized_scanners = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
    })
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

variable "waf_log_destination_arn" {
  description = "The ARN of the firehose delivery stream to store WAF logs"
  type        = string
}