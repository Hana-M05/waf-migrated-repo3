variable "environment" {
  type        = string
  description = "The environment for the CloudWatch (e.g., dev, staging, prod)"
}

variable "waf_acl_arn" {
  type        = string
  description = "The ARN of the WAF ACL to monitor"
}