#############################################################################
# Grafana Alert Rules for WAF Rule Groups
#
# Monitors WAF block rates using Loki datasources
# Creates alert rules for all enabled AWS managed rule groups
# Sends alerts via Grafana contact points (email + future PagerDuty)
#############################################################################

# ============================================================================
# Data Sources: Reference existing Loki datasources in Grafana
# ============================================================================
# These datasources already exist and receive WAF logs from S3 via log shippers
# We reference them by name and extract their UIDs for use in alert rules

data "grafana_data_source" "loki_us1" {
  count = contains(local.datasource_regions, "us1") ? 1 : 0
  name  = "loki-application-flow-logs-us1"
}

data "grafana_data_source" "loki_au1" {
  count = contains(local.datasource_regions, "au1") ? 1 : 0
  name  = "loki-application-flow-logs-au1"
}

data "grafana_data_source" "loki_uk1" {
  count = contains(local.datasource_regions, "uk1") ? 1 : 0
  name  = "loki-application-flow-logs-uk1"
}

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
# Alert Rules: One per enabled WAF rule group
# ============================================================================
# Each rule fires when its block rate exceeds 1% over 2 consecutive 5-min periods
# Metric: (blocks_from_rule / total_requests) * 100 > 1%
#
# This matches the existing CloudWatch alarm logic exactly, enabling
# side-by-side validation before cutover.

resource "grafana_alert_rule" "waf_high_block_rate" {
  for_each = var.grafana_enabled ? local.enabled_aws_rulesets : {}

  # =========================================================================
  # Alert Metadata
  # =========================================================================
  title       = "${each.value.aws_name} - ${var.environment} - High Block Rate"
  description = "Alert when ${each.value.aws_name} blocks more than 1% of requests"
  condition   = "A"  # Which query triggers the alert

  # Fire in OK state (no evaluation required to clear)
  no_data_state   = "NoData"
  exec_err_state  = "Alerting"
  for_duration    = "5m"  # Must be above threshold for 5 minutes

  # Unique alert ID (must be unique within the org)
  uid = "waf-rule-${var.environment}-${each.key}"

  # =========================================================================
  # Query A: Block Rate Calculation
  # =========================================================================
  # Loki LogQL query that calculates: (blocks / total) * 100
  # Selects logs for this specific rule and calculates percentage
  data {
    ref_id      = "A"
    query_type  = "metrics"
    datasource_uid = local.loki_datasource_uid

    # LogQL: sum(rate(blocks[5m])) / sum(rate(total_requests[5m])) * 100
    # This counts WAF logs matching this rule, calculates block percentage
    model = jsonencode({
      expr           = "sum(rate(${each.value.metric_label}[5m])) / sum(rate(waf_requests_total{environment=\"${var.environment}\"}[5m])) * 100"
      interval       = "1m"
      step           = "60"
      refId          = "A"
      legendFormat   = "{{ rule }}"
      datasourceUid  = local.loki_datasource_uid
    })
  }

  # =========================================================================
  # Condition: Alert when expression > 1%
  # =========================================================================
  condition {
    evaluator {
      params = [1]  # Threshold: 1%
      type   = "gt"  # Greater than
    }

    operator {
      type = "and"
    }

    query {
      params = ["A"]
    }
  }

  # =========================================================================
  # Notification: Send to the contact point we created above
  # =========================================================================
  notification_uid = grafana_contact_point.waf_alerts[0].uid
  annotation {
    key   = "description"
    value = "WAF rule ${each.value.aws_name} is blocking > 1% of requests in ${var.environment}"
  }
  annotation {
    key   = "runbook_url"
    value = "https://wiki.brightlysoftware.io/runbooks/waf/high-block-rate"
  }
}

# ============================================================================
# Local values: Support for region-specific datasources
# ============================================================================
# Note: These are referenced from locals.tf as well.
# Map rule groups to their Loki metric labels for LogQL queries

locals {
  # Which Loki datasource regions are enabled for this product
  datasource_regions = var.grafana_enabled ? keys(var.grafana_datasource_ids) : []

  # Determine which Loki datasource UID to use based on environment/region
  # For now, default to us1; future: make region configurable
  loki_datasource_uid = var.grafana_enabled && length(data.grafana_data_source.loki_us1) > 0 ? data.grafana_data_source.loki_us1[0].uid : ""

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
