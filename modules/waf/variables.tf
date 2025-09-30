variable "alb_name" {
  type        = string
  description = "The name of the Application Load Balancer to associate the WAF with"
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
  description = "The environment for the WAF (e.g., dev, staging, prod)"
}

variable "os_specific_ruleset" {
  type        = string
  description = "The OS specific managed ruleset to include (e.g., AWSManagedRulesWindowsRuleSet, AWSManagedRulesLinuxRuleSet)"
}

variable "overrides_common_ruleset" {
  type        = list(string)
  description = "List of rule names from the AWSManagedRulesCommonRuleSet to override with count action"
  default     = []
}

variable "overrides_known_bad_inputs_ruleset" {
  type        = list(string)
  description = "List of rule names from the AWSManagedRulesKnownBadInputsRuleSet to override with count action"
  default     = []
}

variable "overrides_os_specific_ruleset" {
  type        = list(string)
  description = "List of rule names from the OS specific managed ruleset to override with count action"
  default     = []
}

variable "overrides_sqli_ruleset" {
  type        = list(string)
  description = "List of rule names from the AWSManagedRulesSQLiRuleSet to override with count action"
  default     = []
}