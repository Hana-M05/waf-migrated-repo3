variable "alb_arns" {
  description = "List of ALB names to associate with the WAF Web ACL"
  type        = list(string)
  default     = []
}

variable "api_gateway_ids" {
  description = "List of API Gateway v2 IDs to associate with the WAF Web ACL"
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
    }),

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
    }),

    # Protects against common web attacks
    basic_protection = object({
      enabled = bool
      action  = optional(string, "count") # block, count, or allow
      version = optional(string, "Default")
    }),

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

    # Block Tenable scanners
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

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "waf_error_subscribers" {
  description = "List of email addresses to subscribe to WAF error notifications"
  type        = list(string)
  default     = []
}

variable "lambda_processor_arn" {
  description = "ARN of the Lambda function to use as a Firehose record processor. Set to null to disable."
  type        = string
  default     = null
}

variable "s3_backup_bucket_arn" {
  description = "ARN of an S3 bucket to receive a backup of all records (S3BackupMode). Set to null to disable."
  type        = string
  default     = null
}

variable "penalty_box_ip_set_arn" {
  description = "ARN of the WAFv2 penalty-box IP set. Passed through to the WAF module to enable the priority-0 penalty-box rule."
  type        = string
  default     = null
}

variable "penalty_box_action" {
  description = "Action for the penalty-box WAF rule: 'block' to actively block penalised IPs, 'count' to log only (use during initial rollout/validation)."
  type        = string
  default     = "block"
}