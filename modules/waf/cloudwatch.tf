# SNS topic for WAF alarms
# Note: During migration to Grafana, both CloudWatch and Grafana alerts run in parallel
# Set var.grafana_enabled = false to skip CloudWatch creation and rely on Grafana only
resource "aws_sns_topic" "waf_alarms" {
  count = length(var.waf_error_subscribers) > 0 && !var.grafana_enabled ? 1 : 0
  name  = "${var.environment}-waf-alarms"
}

# Subscribe email addresses to WAF alarms topic
resource "aws_sns_topic_subscription" "waf_alarm_emails" {
  for_each = length(var.waf_error_subscribers) > 0 && !var.grafana_enabled ? toset(var.waf_error_subscribers) : []

  topic_arn = aws_sns_topic.waf_alarms[0].arn
  protocol  = "email"
  endpoint  = each.value
}

# Send a specific notification when any managed rule set blocks more than 1% of requests over 10 minutes
# During migration: disabled when var.grafana_enabled = true (Grafana handles alerts instead)
resource "aws_cloudwatch_metric_alarm" "waf_rule_high_block_rate" {
  for_each = length(var.waf_error_subscribers) > 0 && length(local.enabled_aws_rulesets) > 0 && !var.grafana_enabled ? { for ruleset in local.enabled_aws_rulesets : ruleset.aws_name => ruleset } : {}

  alarm_name          = "${each.value.aws_name}-${var.environment}-waf-high-block-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  threshold           = "1" # 1% threshold
  alarm_description   = "Alert when rule AWS-${each.value.aws_name} blocks more than 1% of total requests over two 5 minute periods"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.waf_alarms[0].arn]

  metric_query {
    id          = "blocked_percentage"
    expression  = "(rule_blocked / total_requests) * 100"
    label       = "Rule AWS-${each.value.aws_name} Blocked Percentage"
    return_data = true
  }

  metric_query {
    id = "rule_blocked"
    metric {
      metric_name = "AWS-${each.value.aws_name}-${var.environment}"
      namespace   = "AWS/WAFV2"
      period      = 300
      stat        = "Sum"
    }
  }

  metric_query {
    id = "total_requests"
    metric {
      metric_name = "${var.environment}-waf-acl"
      namespace   = "AWS/WAFV2"
      period      = 300
      stat        = "SampleCount"
    }
  }
}