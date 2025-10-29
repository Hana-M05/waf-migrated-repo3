resource "aws_iam_role" "waf_logging_role" {
  name = "${var.environment}-waf-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "wafv2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "waf_logging_policy" {
  name = "${var.environment}-waf-logging-policy"
  role = aws_iam_role.waf_logging_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation",
        ]
        Resource = [
          var.waf_log_destination_arn,
          "${var.waf_log_destination_arn}/*"
        ]
      }
    ]
  })
}