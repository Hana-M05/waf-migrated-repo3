#############################################################################
# Grafana Alert Rules for WAF Rule Groups
#
# Monitors WAF block rates using Loki datasources
# Creates alert rules for all enabled AWS managed rule groups
# Sends alerts via Grafana contact points (email + future PagerDuty)
#############################################################################

# ============================================================================
# Contact Point: Email notifications for WAF alerts
# ============================================================================
# Routes all WAF alerts to Mohamed and Sam
# Future: Add PagerDuty integration here

resource "grafana_contact_point" "waf_alerts" {
  count = var.grafana_enabled ? 1 : 0

  name = "waf-alerts-${var.environment}"

  email {
    # Hardcoded recipients: Mohamed + Sam
    addresses = [
      "mohamed.elbeltagy@siemens.com",
      "sam.mcmanus@siemens.com"
    ]
  }
}

# ============================================================================
# Alert Rules: One per enabled WAF rule group using grafana_rule_group
# ============================================================================
# Each rule fires when its block rate exceeds 1% over 5 minute window

resource "grafana_rule_group" "waf_high_block_rate" {
  # Convert list of rulesets to map for for_each
  for_each = var.grafana_enabled ? { for ruleset in local.enabled_aws_rulesets : ruleset.friendly_name => ruleset } : {}

  name                = "waf-${each.key}-${var.environment}"
  folder              = "WAF Alerts"
  interval            = "1m"
  evaluation_interval = "1m"

  rule {
    uid         = "waf-rule-${var.environment}-${each.key}"
    title       = "${each.value.aws_name} - ${var.environment} - High Block Rate"
    description = "Alert when ${each.value.aws_name} blocks more than 1% of requests"
    condition   = "A"
    for         = "5m"

    data {
      ref_id         = "A"
      query_type     = "metrics"
      datasource_uid = local.loki_datasource_uid

      model = jsonencode({
        expr           = "sum(rate(${lookup(local.rule_group_metrics, each.key, "")}[5m])) / sum(rate(waf_requests_total{environment=\"${var.environment}\"}[5m])) * 100"
        interval       = "1m"
        step           = "60"
        refId          = "A"
        legendFormat   = "{{ rule }}"
        datasourceUid  = local.loki_datasource_uid
      })
    }

    # Condition: Alert when > 1%
    condition {
      evaluator {
        params = [1]
        type   = "gt"
      }

      operator {
        type = "and"
      }

      query {
        params = ["A"]
      }
    }

    # Notification configuration
    no_data_state  = "NoData"
    exec_err_state = "Alerting"

    annotation {
      key   = "description"
      value = "WAF rule ${each.value.aws_name} is blocking > 1% of requests in ${var.environment}"
    }
    annotation {
      key   = "runbook_url"
      value = "https://wiki.brightlysoftware.io/runbooks/waf/high-block-rate"
    }
  }
}

# ============================================================================
# Local values: Support for region-specific datasources and Grafana alerts
# ============================================================================

locals {
  # Which Loki datasource regions are enabled for this product
  datasource_regions = var.grafana_enabled ? keys(var.grafana_datasource_ids) : []

  # Determine which Loki datasource UID to use based on environment/region
  # For now, default to us1; future: make region configurable per product
  loki_datasource_uid = var.grafana_enabled && length(keys(var.grafana_datasource_ids)) > 0 ? var.grafana_datasource_ids["us1"] : ""

  # Map each rule group to its Loki metric label for querying
  # Format: waf_blocks{rule="AWSManagedRulesCommonRuleSet", action="BLOCK"}
  rule_group_metrics = {
    basic_protection   = "waf_blocks{rule=\"AWSManagedRulesCommonRuleSet\", action=\"BLOCK\"}"
    malicious_requests = "waf_blocks{rule=\"AWSManagedRulesKnownBadInputsRuleSet\", action=\"BLOCK\"}"
    sql_injection      = "waf_blocks{rule=\"AWSManagedRulesSQLiRuleSet\", action=\"BLOCK\"}"
    windows_protection = "waf_blocks{rule=\"AWSManagedRulesWindowsRuleSet\", action=\"BLOCK\"}"
    linux_protection   = "waf_blocks{rule=\"AWSManagedRulesLinuxRuleSet\", action=\"BLOCK\"}"
    ip_reputation      = "waf_blocks{rule=\"AWSManagedRulesAmazonIpReputationList\", action=\"BLOCK\"}"
  }
}
# Note: enabled_aws_rulesets is defined in locals.tf and reused here
