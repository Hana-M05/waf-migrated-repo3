# ---------------------------------------------------------------------------
# Penalty Box — auto-detects scanning/attacking IPs from WAF logs and writes
# them to DynamoDB with a TTL so they can be actioned by a downstream Lambda
# that updates the WAF IP set.
#
# Resources created here:
#   - S3 bucket          (receives log backup from Firehose S3BackupMode)
#   - Lambda function    (Firehose processor — detects violations)
#   - DynamoDB table     (penalty-box-<environment>, stores violating IPs)
#   - IAM role + policy  (Lambda execution role)
#   - CloudWatch log group (Lambda logs, 30-day retention)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# S3 backup bucket — receives a copy of every WAF log record via Firehose
# S3BackupMode. Lives in the same account as the Firehose stream (EM-DEV).
# Note: S3BackupMode is a one-way switch; once enabled it cannot be disabled
# without recreating the Firehose stream.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "penalty_box_logs" {
  bucket = "bsw-waf-penalty-box-logs-${var.environment}"
}

resource "aws_s3_bucket_lifecycle_configuration" "penalty_box_logs" {
  bucket = aws_s3_bucket.penalty_box_logs.id

  rule {
    id     = "expire-waf-logs"
    status = "Enabled"

    filter {} # required by AWS provider v5 — applies rule to all objects

    expiration {
      days = var.log_retention_days
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "penalty_box_logs" {
  bucket = aws_s3_bucket.penalty_box_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "penalty_box_logs" {
  bucket = aws_s3_bucket.penalty_box_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# DynamoDB table — stores violating IPs with a 30-minute TTL.
# The expires_at attribute drives automatic item deletion.
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "penalty_box" {
  name         = "penalty-box-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ip_address"

  attribute {
    name = "ip_address"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "waf-penalty-box"
  }
}

# ---------------------------------------------------------------------------
# Lambda execution role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "penalty_box_lambda" {
  name = "penalty-box-lambda-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "penalty_box_lambda" {
  name = "penalty-box-lambda-policy-${var.environment}"
  role = aws_iam_role.penalty_box_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudWatch Logs — write Lambda execution logs
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/penalty-box-${var.environment}:*"
      },
      {
        # DynamoDB — write violating IPs
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.penalty_box.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Lambda function — Firehose processor (pass-through with DynamoDB side-effect)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "penalty_box_lambda" {
  name              = "/aws/lambda/penalty-box-${var.environment}"
  retention_in_days = 30
}

resource "aws_lambda_function" "penalty_box" {
  function_name = "penalty-box-${var.environment}"
  description   = "Firehose processor: detects scanning IPs in WAF logs and writes to DynamoDB"
  role          = aws_iam_role.penalty_box_lambda.arn

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60 # Firehose processor max timeout is 5 min; 60s is safe for a 5MB batch

  environment {
    variables = {
      DYNAMODB_TABLE        = aws_dynamodb_table.penalty_box.name
      PENALTY_TTL_SECONDS   = tostring(var.penalty_ttl_seconds)
      TIER2_BLOCK_THRESHOLD = tostring(var.tier2_block_threshold)
      TIER3_404_RATIO       = tostring(var.tier3_404_ratio)
      TIER3_MIN_REQUESTS    = tostring(var.tier3_min_requests)
    }
  }

  depends_on = [aws_cloudwatch_log_group.penalty_box_lambda]
}
