variable "alb_names" {
  description = "List of ALB names to associate with the WAF Web ACL"
  type        = list(string)
  default     = []
}

variable "environment" {
  description = "The environment name (e.g., dev, prod, security)"
  type        = string
}

variable "product" {
  description = "The product name, used for naming resources"
  type        = string
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

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}