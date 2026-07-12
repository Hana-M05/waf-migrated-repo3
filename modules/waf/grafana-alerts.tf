#############################################################################
# Grafana Alert Rules for WAF Rule Groups
#
# Monitors WAF block rates using Loki datasources
# Creates alert rules for all enabled AWS managed rule groups
# Sends alerts via Grafana contact points (email)
#############################################################################

# ============================================================================
# Folder: WAF Alerts
# ============================================================================

resource "grafana_folder" "waf_alerts" {
  count = var.grafana_enabled ? 1 : 0
  title = "WAF Alerts"
}

# ============================================================================
# Contact Point: Email notifications for WAF alerts
# ============================================================================

resource "grafana_contact_point" "waf_alerts" {
  count = var.grafana_enabled ? 1 : 0
  name  = "waf-alerts-${var.environment}"

  email {
    addresses = [
      "mohamed.elbeltagy@siemens.com",
      "sam.mcmanus@siemens.com"
    ]
  }
}

# ============================================================================
# Alert Rules: One rule group per enabled WAF rule group
# Fires when block rate > 1% over a 5-minute window
# ============================================================================

resource "grafana_rule_group" "waf_high_block_rate" {
  for_each = var.grafana_enabled ? { for r in local.enabled_aws_rulesets : r.friendly_name => r } : {}

  name             = "waf-${each.key}-${var.environment}"
  folder_uid       = grafana_folder.waf_alerts[0].uid
  interval_seconds = 300 # evaluate every 5 minutes

  rule {
    name           = "${each.value.aws_name} - ${var.environment} - High Block Rate"
    condition      = "B"
    for            = "5m"
    no_data_state  = "NoData"
    exec_err_state = "Alerting"

    annotations = {
      description = "WAF rule ${each.value.aws_name} is blocking > 1% of requests in ${var.environment}"
      runbook_url = "https://wiki.brightlysoftware.io/runbooks/waf/high-block-rate"
    }

    labels = {
      environment = var.environment
      rule_group  = each.value.aws_name
    }

    # Query A: LogQL block rate from Loki
    data {
      ref_id     = "A"
      query_type = ""
      relative_time_range {
        from = 300 # last 5 minutes
        to   = 0
      }
      datasource_uid = local.loki_datasource_uid
      model = jsonencode({
        expr         = "sum(rate(${lookup(local.rule_group_metrics, each.key, "")}[5m])) / sum(rate(waf_requests_total{environment=\"${var.environment}\"}[5m])) * 100"
        intervalMs   = 1000
        maxDataPoints = 43200
        refId        = "A"
      })
    }

    # Expression B: Classic condition — alert when A > 1
    data {
      ref_id     = "B"
      query_type = ""
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "-100" # built-in expression datasource
      model = jsonencode({
        conditions = [
          {
            evaluator = {
              params = [1]
              type   = "gt"
            }
            operator = {
              type = "and"
            }
            query = {
              params = ["A"]
            }
            reducer = {
              params = []
              type   = "last"
            }
            type = "query"
          }
        ]
        datasource = {
          type = "__expr__"
          uid  = "-100"
        }
        hide          = false
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "B"
        type          = "classic_conditions"
      })
    }
  }
}

# ============================================================================
# Local values: datasource UIDs and metric labels
# ============================================================================

locals {
  datasource_regions  = var.grafana_enabled ? keys(var.grafana_datasource_ids) : []
  loki_datasource_uid = var.grafana_enabled && contains(keys(var.grafana_datasource_ids), "us1") ? var.grafana_datasource_ids["us1"] : ""

  rule_group_metrics = {
    basic_protection   = "waf_blocks{rule=\"AWSManagedRulesCommonRuleSet\",action=\"BLOCK\"}"
    malicious_requests = "waf_blocks{rule=\"AWSManagedRulesKnownBadInputsRuleSet\",action=\"BLOCK\"}"
    sql_injection      = "waf_blocks{rule=\"AWSManagedRulesSQLiRuleSet\",action=\"BLOCK\"}"
    windows_protection = "waf_blocks{rule=\"AWSManagedRulesWindowsRuleSet\",action=\"BLOCK\"}"
    linux_protection   = "waf_blocks{rule=\"AWSManagedRulesLinuxRuleSet\",action=\"BLOCK\"}"
    ip_reputation      = "waf_blocks{rule=\"AWSManagedRulesAmazonIpReputationList\",action=\"BLOCK\"}"
  }
}
# Note: enabled_aws_rulesets is defined in locals.tf
