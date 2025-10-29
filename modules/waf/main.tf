resource "aws_wafv2_ip_set" "blacklist" {
  count = var.protection_rules.ip_blocking.enabled && length(var.protection_rules.ip_blocking.ips) > 0 ? 1 : 0

  name               = "ip-blacklist-${var.environment}"
  description        = "IP addresses to block/monitor"
  scope              = var.global ? "CLOUDFRONT" : "REGIONAL"
  ip_address_version = "IPV4"

  addresses = var.protection_rules.ip_blocking.ips

  tags = {
    Name        = "ip-blacklist-${var.environment}"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_wafv2_web_acl" "waf_acl" {
  name        = "${var.environment}-waf-acl"
  scope       = var.global ? "CLOUDFRONT" : "REGIONAL"
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

  # IP Blocking Rule (Priority 1)
  dynamic "rule" {
    for_each = var.protection_rules.ip_blocking.enabled && length(var.protection_rules.ip_blocking.ips) > 0 ? [1] : []
    content {
      name     = "IPBlockingRule"
      priority = local.rule_priorities.ip_blocking

      action {
        dynamic "block" {
          for_each = var.protection_rules.ip_blocking.action == "block" ? [1] : []
          content {}
        }

        dynamic "allow" {
          for_each = var.protection_rules.ip_blocking.action == "allow" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = var.protection_rules.ip_blocking.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.blacklist[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "IPBlockingRule-${var.environment}"
        sampled_requests_enabled   = true
      }
    }
  }

  # Path Blocking Rule (Priority 2)
  dynamic "rule" {
    for_each = var.protection_rules.path_blocking.enabled && length(var.protection_rules.path_blocking.paths) > 0 ? [1] : []
    content {
      name     = "PathBlockingRule"
      priority = local.rule_priorities.path_blocking

      action {
        dynamic "block" {
          for_each = var.protection_rules.path_blocking.action == "block" ? [1] : []
          content {}
        }

        dynamic "allow" {
          for_each = var.protection_rules.path_blocking.action == "allow" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = var.protection_rules.path_blocking.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        # Use OR statement only if there are multiple paths, otherwise use single statement
        dynamic "or_statement" {
          for_each = length(var.protection_rules.path_blocking.paths) > 1 ? [1] : []
          content {
            dynamic "statement" {
              for_each = var.protection_rules.path_blocking.paths
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

        # Use single byte_match_statement if there's only one path
        dynamic "byte_match_statement" {
          for_each = length(var.protection_rules.path_blocking.paths) == 1 ? [var.protection_rules.path_blocking.paths[0]] : []
          content {
            search_string         = byte_match_statement.value
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

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "PathBlockingRule-${var.environment}"
        sampled_requests_enabled   = true
      }
    }
  }

  # AWS Managed Rulesets (Priority 3+)
  dynamic "rule" {
    for_each = local.enabled_aws_rulesets
    content {
      name     = "AWS-${rule.value.aws_name}"
      priority = rule.value.priority

      override_action {
        dynamic "none" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.aws_name
          vendor_name = "AWS"

          dynamic "rule_action_override" {
            for_each = rule.value.overrides
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
        metric_name                = "AWS-${rule.value.aws_name}-${var.environment}"
        sampled_requests_enabled   = true
      }
    }
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "waf_logging" {
  resource_arn = aws_wafv2_web_acl.waf_acl.arn
  log_destination_configs = [
    var.waf_log_destination_arn
  ]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}