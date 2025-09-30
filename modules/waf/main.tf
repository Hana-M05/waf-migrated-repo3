resource "aws_wafv2_ip_set" "blacklist" {
  name               = "ip-blacklist-${var.environment}"
  description        = "IP addresses to block"
  scope              = "CLOUDFRONT"  # Use "REGIONAL" for ALB/API Gateway
  ip_address_version = "IPV4"

  addresses = var.blacklisted_ips

  tags = {
    Name        = "ip-blacklist-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_wafv2_web_acl" "waf_acl" {
  name        = "${var.environment}-waf-acl"
  scope       = "REGIONAL"
  description = "WAF ACL for ${var.environment} environment"

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.environment}-waf-acl"
    sampled_requests_enabled   = true
  }

  rule {
    name    = "BlockSpecificEndpoints"
    priority = 1

    action {
      block {}
    }

    statement {
      or_statement {
        dynamic "statement" {
          for_each = var.blocked_endpoints
          content {
            byte_match_statement {
              search_string         = statement.value
              positional_constraint = "CONTAINS"

              field_to_match {
                uri_path {}
              }

              text_transformation {
                priority = 0
                type     = "NONE"
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockSpecificEndpoints-${var.environment}"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "IPBlacklistRule"
    priority = 2
    action {
      block {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.blacklist.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPBlacklistRule-${var.environment}"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        dynamic "rule_action_override" {
          for_each = var.overrides_common_ruleset
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet-${var.environment}"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"

        dynamic "rule_action_override" {
          for_each = var.overrides_known_bad_inputs_ruleset
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesKnownBadInputsRuleSet-${var.environment}"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-${var.os_specific_ruleset}"
    priority = 5

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = var.os_specific_ruleset
        vendor_name = "AWS"

        dynamic "rule_action_override" {
          for_each = var.overrides_os_specific_ruleset
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-${var.os_specific_ruleset}-${var.environment}"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 6

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"

        dynamic "rule_action_override" {
          for_each = var.overrides_sqli_ruleset
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesSQLiRuleSet-${var.environment}"
      sampled_requests_enabled   = true
    }
  }
}