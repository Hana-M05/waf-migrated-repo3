module "waf" {
  source                             = "./modules/waf"
  alb_name                           = var.alb_name
  custom_rules                       = var.custom_rules
  environment                        = var.environment
  os_specific_ruleset                = var.os_specific_ruleset
  overrides_common_ruleset           = var.overrides_common_ruleset
  overrides_known_bad_inputs_ruleset = var.overrides_known_bad_inputs_ruleset
  overrides_os_specific_ruleset      = var.overrides_os_specific_ruleset
  overrides_sqli_ruleset             = var.overrides_sqli_ruleset
}

module "cloudwatch" {
  source      = "./modules/cloudwatch"
  environment = var.environment
  waf_acl_arn = module.waf.waf_acl_arn

  depends_on = [module.waf]
}