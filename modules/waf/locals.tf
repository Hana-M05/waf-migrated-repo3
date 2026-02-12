locals {
  # A map of user-friendly names to AWS ruleset names
  ruleset_mapping = {
    basic_protection   = "AWSManagedRulesCommonRuleSet"
    malicious_requests = "AWSManagedRulesKnownBadInputsRuleSet"
    sql_injection      = "AWSManagedRulesSQLiRuleSet"
    windows_protection = "AWSManagedRulesWindowsRuleSet"
    linux_protection   = "AWSManagedRulesLinuxRuleSet"
    ip_reputation      = "AWSManagedRulesAmazonIpReputationList"
  }

  unauthorized_scanner_ip_ranges = [
    # Tenable Scanner
    "13.115.104.128/25",
    "35.73.219.128/25",
    "13.213.79.0/24",
    "18.139.204.0/25",
    "54.255.254.0/26",
    "13.210.1.64/26",
    "3.106.118.128/25",
    "3.26.100.0/24",
    "3.108.37.0/24",
    "3.98.92.0/25",
    "35.182.14.64/26",
    "3.251.224.0/24",
    "18.168.180.128/25",
    "18.168.224.128/25",
    "3.9.159.128/25",
    "35.177.219.0/26",
    "18.194.95.64/26",
    "3.124.123.128/25",
    "3.67.7.128/25",
    "54.93.254.128/26",
    "34.201.223.128/25",
    "44.192.244.0/24",
    "44.206.3.0/24",
    "54.175.125.192/26",
    "13.59.252.0/25",
    "18.116.198.0/24",
    "3.132.217.0/25",
    "13.56.21.128/25",
    "34.223.64.0/25",
    "35.82.51.128/25",
    "35.86.126.0/24",
    "35.93.174.0/24",
    "44.242.181.128/25",
    "15.228.125.0/24",
    "51.112.93.0/24",
    "162.159.129.83/32",
    "162.159.130.83/32",
    "162.159.140.26/32",
    "172.66.0.26/32",
    # Veracode Scanner
    "34.195.146.191/32",
    "35.156.203.105/32",
    "3.32.105.199/32",
    "44.219.184.144/28",
    "34.195.146.191/32",
    "3.79.58.176/28",
    "35.156.203.105/32",
    "18.210.137.174/32",
    "144.121.23.147/32",
    "3.93.86.183/32",
    "34.226.252.43/32",
    "52.205.76.209/32"
  ]

  unauthorized_scanner_user_agents = [
    "UT-Dorkbot/1.2",
    "libredtail-http"
  ]

  # Define rule priorities to ensure consistent ordering
  rule_priorities = {
    ip_blocking                 = 1
    path_blocking               = 2
    geolocation_blocking        = 3
    block_unauthorized_scanners = 4
    rate_limiting_base          = 100 # Potentially enables multiple rate limiting rules, so needs multiple priority rule space
    basic_protection            = 200
    malicious_requests          = 201
    sql_injection               = 202
    windows_protection          = 203
    linux_protection            = 205
    ip_reputation               = 206
    captcha_base                = 300 # Needs to be at the end so all block rules are evaluated
  }

  # Build enabled AWS managed rulesets - FIXED VERSION
  enabled_aws_rulesets = [
    for name, aws_name in local.ruleset_mapping : {
      friendly_name = name
      aws_name      = aws_name
      priority      = local.rule_priorities[name]
      action        = var.protection_rules[name].action
      overrides     = lookup(var.disabled_rules, name, [])
    } if lookup(var.protection_rules, name, { enabled = false }).enabled
  ]
}