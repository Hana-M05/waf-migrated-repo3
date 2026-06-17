variable "environment" {
  description = "Environment name used to namespace all resources (e.g. energy-manager-dev-us-east-1)"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain WAF log backups in the penalty-box S3 bucket"
  type        = number
  default     = 90
}

variable "penalty_ttl_seconds" {
  description = "Seconds until a penalised IP is automatically removed from DynamoDB (default: 30 min)"
  type        = number
  default     = 1800
}

variable "tier2_block_threshold" {
  description = "Number of WAF BLOCK actions in a single Firehose batch that triggers a Tier 2 penalty"
  type        = number
  default     = 20
}

variable "tier3_404_ratio" {
  description = "Fraction of requests (0–1) that must be heuristic-404 to trigger a Tier 3 penalty"
  type        = number
  default     = 0.40
}

variable "tier3_min_requests" {
  description = "Minimum requests in a batch before Tier 3 ratio is evaluated"
  type        = number
  default     = 20
}
