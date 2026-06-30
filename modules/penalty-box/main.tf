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
# SSM parameter — known-good IPs that should never be added to the penalty box.
# Shared IPs (ZScaler proxies, Cisco VPN, internal scanners) exit through a
# handful of IPs used by many users, which would cause false positives if penalised.
# The Lambda reads this list on cold start and skips DynamoDB writes for these IPs.
# WAF rules are NOT affected — individual bad requests from these IPs are still blocked.
# Update the value in SSM to change the list without redeploying the Lambda.
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "known_good_ips" {
  name        = "/waf/penalty-box/${var.environment}/known-good-ips"
  description = "Comma-separated CIDRs that should never be added to the WAF penalty box"
  type        = "StringList"

  # ZScaler proxy exit nodes (shared by many users) + Cisco VPN + QA EIP
  value = join(",", [
    # ZScaler IPv4 — https://config.zscaler.com/zscaler.net/cenr
    "136.226.0.0/16",
    "165.225.0.0/17",
    "165.225.128.0/17",
    "147.161.128.0/17",
    "165.225.192.0/18",
    "185.46.212.0/22",
    "165.225.8.0/21",
    "165.225.16.0/21",
    "165.225.24.0/21",
    "165.225.80.0/21",
    "165.225.88.0/21",
    "165.225.196.0/22",
    "165.225.200.0/22",
    "165.225.204.0/22",
    "165.225.72.0/22",
    "165.225.76.0/22",
    "147.161.160.0/20",
    "104.129.192.0/20",
    "185.46.212.0/24",
    "185.46.213.0/24",
    "185.46.214.0/24",
    "185.46.215.0/24",
    "165.225.32.0/20",
    "165.225.48.0/20",
    "165.225.64.0/20",
    "165.225.96.0/20",
    "165.225.112.0/20",
    "165.225.128.0/20",
    "165.225.144.0/20",
    "165.225.160.0/20",
    "165.225.176.0/20",
    "165.225.208.0/20",
    "165.225.224.0/20",
    "165.225.240.0/20",
    "147.161.128.0/20",
    "147.161.144.0/20",
    "147.161.160.0/20",
    "147.161.176.0/20",
    "147.161.192.0/20",
    "147.161.208.0/20",
    "147.161.224.0/20",
    "147.161.240.0/20",
    "136.226.0.0/20",
    "136.226.16.0/20",
    "136.226.32.0/20",
    "136.226.48.0/20",
    "136.226.64.0/20",
    "136.226.80.0/20",
    "136.226.96.0/20",
    "136.226.112.0/20",
    "136.226.128.0/20",
    # Cisco VPN
    "3.92.93.50/32",
    # QA EIP
    "3.136.75.45/32",
  ])

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "waf-penalty-box"
  }
}

# ---------------------------------------------------------------------------
# WAFv2 IP set — holds penalised IPs so the WAF can block them at priority 0.
# The Lambda updates this set at runtime; Terraform MUST NOT overwrite the
# addresses list on every apply (lifecycle ignore_changes).
# ---------------------------------------------------------------------------
resource "aws_wafv2_ip_set" "penalty_box" {
  name               = "penalty-box-${var.environment}"
  description        = "IPs currently in the penalty box - managed at runtime by Lambda"
  scope              = var.waf_scope
  ip_address_version = "IPV4"
  addresses          = [] # bootstrapped empty; Lambda fills at runtime

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform+lambda"
    Purpose     = "waf-penalty-box"
  }

  lifecycle {
    ignore_changes = [addresses]
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
      },
      {
        # SSM — read the known-good IP list on Lambda cold start
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = aws_ssm_parameter.known_good_ips.arn
      },
      {
        # WAFv2 — add penalised IPs to the penalty-box IP set
        Effect = "Allow"
        Action = [
          "wafv2:GetIPSet",
          "wafv2:UpdateIPSet"
        ]
        Resource = aws_wafv2_ip_set.penalty_box.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Lambda deployment package — built by Terraform from committed source.
# The archive provider zips lambda_function.py at plan time so no manual
# build step is required and the pipeline never needs a pre-built artifact.
# ---------------------------------------------------------------------------
data "archive_file" "penalty_box_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda/lambda.zip"
}

# ---------------------------------------------------------------------------
# Lambda function — Firehose processor (pass-through with DynamoDB side-effect)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "penalty_box_lambda" {
  name              = "/aws/lambda/penalty-box-${var.environment}"
  retention_in_days = 90
}

resource "aws_lambda_function" "penalty_box" {
  function_name = "penalty-box-${var.environment}"
  description   = "Firehose processor: detects scanning IPs in WAF logs and writes to DynamoDB"
  role          = aws_iam_role.penalty_box_lambda.arn

  filename         = data.archive_file.penalty_box_lambda.output_path
  source_code_hash = data.archive_file.penalty_box_lambda.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60 # Firehose processor max timeout is 5 min; 60s is safe for a 5MB batch

  environment {
    variables = {
      DYNAMODB_TABLE            = aws_dynamodb_table.penalty_box.name
      PENALTY_TTL_SECONDS       = tostring(var.penalty_ttl_seconds)
      TIER2_BLOCK_THRESHOLD     = tostring(var.tier2_block_threshold)
      TIER2_BLOCK_RATIO         = tostring(var.tier2_block_ratio)
      KNOWN_GOOD_IPS_SSM_PARAM  = aws_ssm_parameter.known_good_ips.name
      WAF_IP_SET_ID             = aws_wafv2_ip_set.penalty_box.id
      WAF_IP_SET_NAME           = aws_wafv2_ip_set.penalty_box.name
      WAF_SCOPE                 = var.waf_scope
    }
  }

  depends_on = [aws_cloudwatch_log_group.penalty_box_lambda]
}

# ---------------------------------------------------------------------------
# Unban Lambda — runs every 5 minutes, removes expired IPs from WAFv2
# ---------------------------------------------------------------------------
data "archive_file" "penalty_box_unban_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/unban_function.py"
  output_path = "${path.module}/lambda/unban_lambda.zip"
}

resource "aws_cloudwatch_log_group" "penalty_box_unban_lambda" {
  name              = "/aws/lambda/penalty-box-unban-${var.environment}"
  retention_in_days = 30
}

resource "aws_iam_role" "penalty_box_unban_lambda" {
  name = "penalty-box-unban-lambda-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "penalty_box_unban_lambda" {
  name = "penalty-box-unban-lambda-policy-${var.environment}"
  role = aws_iam_role.penalty_box_unban_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudWatch Logs — write Lambda execution logs
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/penalty-box-unban-${var.environment}:*"
      },
      {
        # DynamoDB — GetItem to check expiry; DeleteItem for cleanup alongside TTL
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.penalty_box.arn
      },
      {
        # WAFv2 — read current IP set and update it to remove expired IPs
        Effect   = "Allow"
        Action   = ["wafv2:GetIPSet", "wafv2:UpdateIPSet"]
        Resource = aws_wafv2_ip_set.penalty_box.arn
      }
    ]
  })
}

resource "aws_lambda_function" "penalty_box_unban" {
  function_name = "penalty-box-unban-${var.environment}"
  description   = "Removes expired IPs from the WAFv2 penalty-box IP set every 5 minutes"
  role          = aws_iam_role.penalty_box_unban_lambda.arn

  filename         = data.archive_file.penalty_box_unban_lambda.output_path
  source_code_hash = data.archive_file.penalty_box_unban_lambda.output_base64sha256
  handler          = "unban_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      DYNAMODB_TABLE  = aws_dynamodb_table.penalty_box.name
      WAF_IP_SET_ID   = aws_wafv2_ip_set.penalty_box.id
      WAF_IP_SET_NAME = aws_wafv2_ip_set.penalty_box.name
      WAF_SCOPE       = var.waf_scope
    }
  }

  depends_on = [aws_cloudwatch_log_group.penalty_box_unban_lambda]
}

resource "aws_lambda_permission" "penalty_box_unban_scheduler" {
  statement_id  = "AllowEventBridgeScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.penalty_box_unban.function_name
  principal     = "scheduler.amazonaws.com"
}

resource "aws_iam_role" "penalty_box_unban_scheduler" {
  name = "penalty-box-unban-scheduler-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "penalty_box_unban_scheduler" {
  name = "penalty-box-unban-scheduler-policy-${var.environment}"
  role = aws_iam_role.penalty_box_unban_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.penalty_box_unban.arn
    }]
  })
}

resource "aws_scheduler_schedule" "penalty_box_unban" {
  name                         = "penalty-box-unban-${var.environment}"
  description                  = "Fires every 5 minutes to remove expired IPs from the WAFv2 penalty-box IP set"
  schedule_expression          = "rate(5 minutes)"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.penalty_box_unban.arn
    role_arn = aws_iam_role.penalty_box_unban_scheduler.arn
  }
}
