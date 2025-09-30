variable "alb_name" {
  type        = string
  description = "The name of the Application Load Balancer"
}

variable "blacklisted_ips" {
  type        = list(string)
  description = "List of IPs or CIDR blocks to be blacklisted"
  default     = []
}

variable "blocked_endpoints" {
  type        = list(string)
  description = "List of URI paths to be blocked"
  default     = []
}

variable "custom_rules" {
  type        = any
  description = "List of custom WAF rules to be created"
  default     = []
}

variable "environment" {
  type        = string
  description = "The environment for the deployment (e.g., dev, staging, prod)"
}

variable "os_specific_ruleset" {
  type        = string
  description = "The OS specific managed ruleset to use (e.g., AWSManagedRulesWindowsRuleSet)"
}

variable "overrides_common_ruleset" {
  type        = list(string)
  description = "List of rule names to override in the Common Rule Set"
}

variable "overrides_known_bad_inputs_ruleset" {
  type        = list(string)
  description = "List of rule names to override in the Known Bad Inputs Rule Set"
}

variable "overrides_os_specific_ruleset" {
  type        = list(string)
  description = "List of rule names to override in the OS Specific Rule Set"
}

variable "overrides_sqli_ruleset" {
  type        = list(string)
  description = "List of rule names to override in the SQLi Rule Set"
}

variable "region" {
  type        = string
  description = "The AWS region to deploy resources in"
}