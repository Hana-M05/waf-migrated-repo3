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

  # WAF ACL level visibility config - THIS WAS MISSING!
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.environment}-waf-acl"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

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
    priority = 2

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
    priority = 3

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
    priority = 4

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

  # Dynamic rules for custom rules
  dynamic "rule" {
    for_each = var.custom_rules
    content {
      name     = rule.value.name
      priority = rule.value.priority

      action {
        dynamic "allow" {
          for_each = rule.value.action == "allow" ? [1] : []
          content {}
        }
        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        # IP Set Reference Statement
        dynamic "ip_set_reference_statement" {
          for_each = can(rule.value.statement_config.ip_set_reference_statement) ? [rule.value.statement_config.ip_set_reference_statement] : []
          content {
            arn = ip_set_reference_statement.value.arn
          }
        }

        # Byte Match Statement (for string matching)
        dynamic "byte_match_statement" {
          for_each = can(rule.value.statement_config.string_match) ? [rule.value.statement_config.string_match] : []
          content {
            search_string         = byte_match_statement.value.search_string
            positional_constraint = byte_match_statement.value.comparison_operator

            field_to_match {
              dynamic "uri_path" {
                for_each = byte_match_statement.value.field_to_match.type == "uri_path" ? [1] : []
                content {}
              }
              dynamic "query_string" {
                for_each = byte_match_statement.value.field_to_match.type == "query_string" ? [1] : []
                content {}
              }
              dynamic "single_header" {
                for_each = byte_match_statement.value.field_to_match.type == "header" ? [1] : []
                content {
                  name = byte_match_statement.value.field_to_match.data
                }
              }
              dynamic "body" {
                for_each = byte_match_statement.value.field_to_match.type == "body" ? [1] : []
                content {}
              }
            }

            dynamic "text_transformation" {
              for_each = byte_match_statement.value.text_transformations
              content {
                priority = text_transformation.value.priority
                type     = text_transformation.value.type
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "CustomRule-${rule.value.name}-${var.environment}"
        sampled_requests_enabled   = true
      }
    }
  }
}