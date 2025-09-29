alb_name = "security-alb"
custom_rules = [
  # {
  #   name      = "AE-wafBlacklistRule"
  #   priority  = 5
  #   action    = "block"
  #   rule_type = "custom"
  #   statement_config = {
  #     ip_set_reference_statement = {
  #       arn = "arn:aws:wafv2:us-east-1:748037917842:regional/ipset/AE-wafBlacklistRule/20826765-82f0-458b-b0a0-b6240f26e5a1"
  #     }
  #   }
  # },
  {
    name      = "block-strongholddm-login-endpoint"
    priority  = 6
    action    = "block"
    rule_type = "custom"
    statement_config = {
      string_match = {
        search_string = "/StrongholdDM/api/login"
        field_to_match = {
          type = "uri_path"
        }
        text_transformations = [{
          priority = 0
          type     = "NONE"
        }]
        comparison_operator = "CONTAINS"
      }
    }
  }
]
environment                        = "security"
os_specific_ruleset                = "AWSManagedRulesWindowsRuleSet"
overrides_common_ruleset           = ["NoUserAgent_HEADER", "SizeRestrictions_BODY", "UserAgent_BadBots_HEADER"]
overrides_known_bad_inputs_ruleset = ["Log4JRCE_BODY"]
overrides_os_specific_ruleset      = ["WindowsShellCommands_BODY"]
overrides_sqli_ruleset             = ["SQLi_BODY"]
region                             = "us-east-1"