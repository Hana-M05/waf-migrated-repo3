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
  description = "Minimum number of WAF BLOCK actions in a single Firehose batch before Tier 2 is considered (must also exceed tier2_block_ratio)"
  type        = number
  default     = 20
}

variable "tier2_block_ratio" {
  description = "Minimum fraction (0–1) of an IP's requests that must be WAF BLOCKs to trigger a Tier 2 penalty. Guards against penalising high-volume gateway IPs where a small percentage of requests happen to be blocked (e.g. 20 blocks / 1000 requests = 2% → not penalised)."
  type        = number
  default     = 0.20

  validation {
    condition     = var.tier2_block_ratio > 0 && var.tier2_block_ratio <= 1
    error_message = "tier2_block_ratio must be between 0 (exclusive) and 1 (inclusive)."
  }
}

# Tier 3 variables removed — on hold for the walk phase.
# Detecting 404-rate requires a reliable HTTP response-code log source
# (ALB/API GW access logs) which is not consistently enabled across all customers.
# WAF logs only expose codes for WAF-generated responses (BLOCKs); origin 404s
# are invisible to WAF. Will be re-added once a consistent log source is confirmed.

variable "waf_scope" {
  description = "WAFv2 scope for the penalty-box IP set: REGIONAL (ALB/API Gateway) or CLOUDFRONT"
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.waf_scope)
    error_message = "waf_scope must be REGIONAL or CLOUDFRONT."
  }
}
