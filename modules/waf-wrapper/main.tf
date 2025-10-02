module "waf" {
  source = "../waf"

  alb_names        = var.alb_names
  disabled_rules   = var.disabled_rules
  environment      = var.environment
  region           = var.region
  protection_rules = var.protection_rules
}

module "cloudwatch" {
  source = "../cloudwatch"

  environment = var.environment
  waf_acl_arn = module.waf.waf_acl_arn

  depends_on = [module.waf]
}