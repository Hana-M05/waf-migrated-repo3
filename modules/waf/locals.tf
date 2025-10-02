locals {
  # A map of user-friendly names to AWS ruleset names
  ruleset_mapping = {
    basic_protection   = "AWSManagedRulesCommonRuleSet"
    malicious_requests = "AWSManagedRulesKnownBadInputsRuleSet"
    sql_injection      = "AWSManagedRulesSQLiRuleSet"
    windows_protection = "AWSManagedRulesWindowsRuleSet"
    linux_protection   = "AWSManagedRulesLinuxRuleSet"
  }

  # Define rule priorities to ensure consistent ordering
  rule_priorities = {
    ip_blocking        = 1
    path_blocking      = 2
    basic_protection   = 3
    malicious_requests = 4
    sql_injection      = 5
    windows_protection = 6
    linux_protection   = 7
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