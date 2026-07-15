#############################################################################
# Grafana Alert Rules for WAF Rule Groups
#
# Monitors WAF block rates using Loki datasources
# Creates alert rules for all enabled AWS managed rule groups
# Sends alerts via Grafana contact points (email)
#############################################################################

# ============================================================================
# Folders: WAF Alerts / environment (nested)
# ============================================================================

resource "grafana_folder" "waf_alerts" {
  count = var.grafana_enabled ? 1 : 0
  title = "WAF Alerts"
}

resource "grafana_folder" "waf_alerts_environment" {
  count             = var.grafana_enabled ? 1 : 0
  title             = var.environment
  parent_folder_uid = grafana_folder.waf_alerts[0].uid
}

# ============================================================================
# Contact Point: Email notifications for WAF alerts
# ============================================================================

resource "grafana_contact_point" "waf_alerts" {
  count = var.grafana_enabled && length(var.waf_error_subscribers) > 0 ? 1 : 0
  name  = "waf-alerts-${var.environment}"

  email {
    addresses = var.waf_error_subscribers
  }
}

# ============================================================================
# Alert Rules: One rule group per enabled WAF rule group
# Fires when block rate > 1% over a 5-minute window
# ============================================================================

resource "grafana_rule_group" "waf_high_block_rate" {
  for_each = var.grafana_enabled ? { for r in local.enabled_aws_rulesets : r.friendly_name => r } : {}

  name             = "waf-${each.key}-${var.environment}"
  folder_uid       = grafana_folder.waf_alerts_environment[0].uid
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

    notification_settings {
      contact_point = grafana_contact_point.waf_alerts[0].name
    }

    # Query A: LogQL block rate from Loki
    data {
      ref_id     = "A"
      query_type = "range"
      relative_time_range {
        from = 300 # last 5 minutes
        to   = 0
      }
      datasource_uid = local.loki_datasource_uid
      model = jsonencode({
        expr          = "sum(rate({webacl=\"${var.environment}-waf-acl\"} | json | action=\"BLOCK\" | terminating_rule_id=\"AWS-${each.value.aws_name}\" [5m])) / sum(rate({webacl=\"${var.environment}-waf-acl\"} [5m])) * 100"
        queryType     = "range"
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "A"
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

}
# Note: enabled_aws_rulesets is defined in locals.tf
