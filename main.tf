module "waf" {
  source           = "./modules/waf"
  for_each         = local.environments
  
  alb_names        = each.value.alb_names
  disabled_rules   = each.value.disabled_rules
  environment      = each.value.environment
  region           = each.value.region
  protection_rules = each.value.protection_rules
}

module "cloudwatch" {
  source      = "./modules/cloudwatch"
  for_each         = local.environments
  
  environment = each.value.environment
  waf_acl_arn = module.waf[each.key].waf_acl_arn

  depends_on = [module.waf]
}