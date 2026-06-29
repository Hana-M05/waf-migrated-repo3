variable "alb_arns" {
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
    # Penalty box rule — automated IP blocking managed by the penalty-box Lambda
    # Optional so existing environments without this field still validate.
    penalty_box = optional(object({
      enabled = bool
      action  = optional(string, "count") # block or count
    }))

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

    # Geolocation blocking rule
    geolocation_blocking = object({
      enabled   = bool
      action    = optional(string, "count") # block, count, or allow
      countries = optional(list(string), [])
    }),

    # Custom rate limiting rules
    rate_limiting = object({
      enabled = bool
      rules = list(object({
        name                  = string
        action                = string
        limit                 = number
        aggregate_key_type    = string # IP, FORWARDED_IP, AUTHENTICATED_USER, or CUSTOM_KEYS
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
        uri_paths = optional(list(string), [])
        custom_keys = optional(list(object({
          type              = string           # IP, HEADER, JA3_FINGERPRINT, or FORWARDED_IP
          header_name       = optional(string)
          fallback_behavior = optional(string) # MATCH or NO_MATCH (for JA3_FINGERPRINT)
        })), [])
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
      version = optional(string, "Default")
    })

    # Blocks known malicious requests
    malicious_requests = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
      version = optional(string, "Default")
    }),

    # Protects against SQL injection attacks
    sql_injection = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
      version = optional(string, "Default")
    }),

    # Windows system specific protection
    windows_protection = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
      version = optional(string, "Default")
    }),

    # Linux system specific protection
    linux_protection = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
      version = optional(string, "Default")
    }),

    # IP reputation based protection
    ip_reputation = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
      version = optional(string, "Default")
    }),

    # Block unauthorized scanners
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
    ip_reputation      = optional(list(string), [])
  })
  default = {}
}

variable "redacted_headers" {
  description = "List of HTTP header names to redact from WAF logs"
  type        = list(string)
  default     = []
}

variable "waf_error_subscribers" {
  description = "List of email addresses to subscribe to WAF error notifications"
  type        = list(string)
  default     = []
}

variable "waf_log_destination_arn" {
  description = "The ARN of the firehose delivery stream to store WAF logs"
  type        = string
}

variable "penalty_box_ip_set_arn" {
  description = "ARN of the WAFv2 IP set managed by the penalty-box module. When set, a rule is added at priority 0 for IPs currently in the set."
  type        = string
  default     = null
}

variable "penalty_box_action" {
  description = "Action for the penalty-box WAF rule: 'block' to actively block penalised IPs, 'count' to log only (use during initial rollout/validation)."
  type        = string
  default     = "block"

  validation {
    condition     = contains(["block", "count"], var.penalty_box_action)
    error_message = "penalty_box_action must be 'block' or 'count'."
  }
}