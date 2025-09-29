resource "aws_cloudwatch_log_group" "waf_log_group" {
  name              = "aws-waf-logs-client-${var.environment}"
  retention_in_days = 30
}


resource "aws_wafv2_web_acl_logging_configuration" "waf_logs" {
  log_destination_configs = ["${aws_cloudwatch_log_group.waf_log_group.arn}:*"]
  resource_arn            = var.waf_acl_arn

  depends_on = [aws_cloudwatch_log_resource_policy.waf_log_policy]
}

resource "aws_cloudwatch_log_resource_policy" "waf_log_policy" {
  policy_name = "waf-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = aws_cloudwatch_log_group.waf_log_group.arn
        Principal = {
          Service = "wafv2.amazonaws.com"
        }
      }
    ]
  })
}
