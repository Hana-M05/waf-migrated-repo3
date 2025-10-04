resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "waf_logs" {
  bucket = "aws-waf-logs-brightly-${var.product}-${var.environment}-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "WAF Logs"
  }
}

resource "aws_s3_bucket_versioning" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    id     = "waf_logs_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""  # Empty prefix means all objects
    }

    transition {
      days          = local.waf_log_glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = local.waf_log_retention_days
    }
  }
}