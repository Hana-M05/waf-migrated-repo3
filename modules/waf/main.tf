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

resource "aws_wafv2_ip_set" "unauthorized_scanner_ip_ranges" {
  count = var.protection_rules.block_unauthorized_scanners.enabled ? 1 : 0

  name               = "unauthorized-scanner-blocklist-${var.environment}"
  description        = "Unauthorized scanner IP addresses to block"
  scope              = var.global ? "CLOUDFRONT" : "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = local.unauthorized_scanner_ip_ranges

  tags = {
    Name        = "unauthorized-scanner-blocklist-${var.environment}"
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

  # Geolocation Blocking Rule (Priority 3)
  dynamic "rule" {
    for_each = var.protection_rules.geolocation_blocking.enabled && length(var.protection_rules.geolocation_blocking.countries) > 0 ? [1] : []
    content {
      name     = "GeolocationBlockingRule"
      priority = local.rule_priorities.geolocation_blocking

      action {
        block {}
      }

      statement {
        # If action="block": block traffic FROM the specified countries
        # If action="allow": block traffic NOT FROM the specified countries (allowlist behavior)
        dynamic "geo_match_statement" {
          for_each = var.protection_rules.geolocation_blocking.action == "block" ? [1] : []
          content {
            country_codes = var.protection_rules.geolocation_blocking.countries
          }
        }

        dynamic "not_statement" {
          for_each = var.protection_rules.geolocation_blocking.action == "allow" ? [1] : []
          content {
            statement {
              geo_match_statement {
                country_codes = var.protection_rules.geolocation_blocking.countries
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "GeolocationBlockingRule-${var.environment}"
        sampled_requests_enabled   = true
      }
    }
  }

  # Block Unauthorized Scanners by IP Rule (Priority 4)
  dynamic "rule" {
    for_each = var.protection_rules.block_unauthorized_scanners.enabled ? [1] : []
    content {
      name     = "UnauthorizedScannerIPBlockRule"
      priority = local.rule_priorities.block_unauthorized_scanners
      action {
        dynamic "block" {
          for_each = var.protection_rules.block_unauthorized_scanners.action == "block" ? [1] : []
          content {}
        }

        dynamic "allow" {
          for_each = var.protection_rules.block_unauthorized_scanners.action == "allow" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = var.protection_rules.block_unauthorized_scanners.action == "count" ? [1] : []
          content {}
        }
      }
      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.unauthorized_scanner_ip_ranges[0].arn
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "UnauthorizedScannerIPBlockRule-${var.environment}"
        sampled_requests_enabled   = true
      }
    }
  }

  # Block Unauthorized Scanners by Header Rule (Priority 5)
  dynamic "rule" {
    for_each = var.protection_rules.block_unauthorized_scanners.enabled && length(local.unauthorized_scanner_header_checks) > 0 ? [1] : []
    content {
      name     = "UnauthorizedScannerHeaderBlockRule"
      priority = local.rule_priorities.block_unauthorized_scanners + 1

      action {
        dynamic "block" {
          for_each = var.protection_rules.block_unauthorized_scanners.action == "block" ? [1] : []
          content {}
        }

        dynamic "allow" {
          for_each = var.protection_rules.block_unauthorized_scanners.action == "allow" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = var.protection_rules.block_unauthorized_scanners.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        # Use OR statement if there are multiple header checks, otherwise use single statement
        dynamic "or_statement" {
          for_each = length(local.unauthorized_scanner_header_checks) > 1 ? [1] : []
          content {
            dynamic "statement" {
              for_each = local.unauthorized_scanner_header_checks
              content {
                byte_match_statement {
                  search_string         = statement.value.value
                  positional_constraint = "CONTAINS"

                  field_to_match {
                    single_header {
                      name = statement.value.header
                    }
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

        # Use single byte_match_statement if there's only one header check
        dynamic "byte_match_statement" {
          for_each = length(local.unauthorized_scanner_header_checks) == 1 ? [local.unauthorized_scanner_header_checks[0]] : []
          content {
            search_string         = byte_match_statement.value.value
            positional_constraint = "CONTAINS"

            field_to_match {
              single_header {
                name = byte_match_statement.value.header
              }
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
        metric_name                = "UnauthorizedScannerHeaderBlockRule-${var.environment}"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rate Limiting Rules (Priority 100+)
  # Create a separate rule for each rate limiting configuration
  dynamic "rule" {
    for_each = var.protection_rules.rate_limiting.enabled && length(var.protection_rules.rate_limiting.rules) > 0 ? var.protection_rules.rate_limiting.rules : []
    iterator = rate_rule
    content {
      name     = rate_rule.value.name
      priority = local.rule_priorities.rate_limiting_base + rate_rule.key

      action {
        dynamic "block" {
          for_each = rate_rule.value.action == "block" ? [1] : []
          content {
            custom_response {
              response_code = 429
            }
          }
        }

        dynamic "count" {
          for_each = rate_rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        rate_based_statement {
          limit                 = rate_rule.value.limit
          aggregate_key_type    = rate_rule.value.aggregate_key_type
          evaluation_window_sec = rate_rule.value.evaluation_window_sec

          # Scope down statement with AND conditions (if provided)
          dynamic "scope_down_statement" {
            for_each = rate_rule.value.uri_path != null || rate_rule.value.method != null || rate_rule.value.header != null ? [1] : []
            content {
              and_statement {
                # URI path match statement
                dynamic "statement" {
                  for_each = rate_rule.value.uri_path != null && rate_rule.value.uri_path.search_string != null ? [rate_rule.value.uri_path] : []
                  content {
                    byte_match_statement {
                      search_string         = statement.value.search_string
                      positional_constraint = statement.value.positional_constraint

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

                # HTTP method match statement
                dynamic "statement" {
                  for_each = rate_rule.value.method != null ? [rate_rule.value.method] : []
                  content {
                    byte_match_statement {
                      search_string         = statement.value
                      positional_constraint = "EXACTLY"

                      field_to_match {
                        method {}
                      }

                      text_transformation {
                        priority = 0
                        type     = "NONE"
                      }
                    }
                  }
                }

                # Header match statement
                dynamic "statement" {
                  for_each = rate_rule.value.header != null && rate_rule.value.header.name != null ? [rate_rule.value.header] : []
                  content {
                    byte_match_statement {
                      search_string         = statement.value.search_string
                      positional_constraint = statement.value.positional_constraint

                      field_to_match {
                        single_header {
                          name = statement.value.name
                        }
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
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${rate_rule.value.name}-${var.environment}"
        sampled_requests_enabled   = true
      }
    }
  }

  # AWS Managed Rulesets (Priority 200+)
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
          version     = contains(["default", "latest", ""], lower(trimspace(rule.value.version))) ? null : trimspace(rule.value.version)

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

  # CAPTCHA Rules (Priority 300+)
  # Create a separate rule for each CAPTCHA configuration
  dynamic "rule" {
    for_each = var.protection_rules.captcha.enabled && length(var.protection_rules.captcha.rules) > 0 ? var.protection_rules.captcha.rules : []
    iterator = captcha_rule
    content {
      name     = captcha_rule.value.name
      priority = local.rule_priorities.captcha_base + captcha_rule.key

      action {
        captcha {
          custom_request_handling {
            insert_header {
              name  = "x-captcha-challenge"
              value = "true"
            }
          }
        }
      }

      statement {
        and_statement {
          # URI path match statement
          dynamic "statement" {
            for_each = captcha_rule.value.uri_path != null && captcha_rule.value.uri_path.search_string != null ? [captcha_rule.value.uri_path] : []
            content {
              byte_match_statement {
                search_string         = statement.value.search_string
                positional_constraint = statement.value.positional_constraint

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

          # Header match statement
          dynamic "statement" {
            for_each = captcha_rule.value.header != null && captcha_rule.value.header.name != null ? [captcha_rule.value.header] : []
            content {
              byte_match_statement {
                search_string         = statement.value.search_string
                positional_constraint = statement.value.positional_constraint

                field_to_match {
                  single_header {
                    name = statement.value.name
                  }
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
        metric_name                = "${captcha_rule.value.name}-${var.environment}"
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

  dynamic "redacted_fields" {
    for_each = var.redacted_headers
    content {
      single_header {
        name = lower(redacted_fields.value)
      }
    }
  }
}