module "s3" {
  source = "../s3"

  environment = var.environment
  product     = var.product
}

module "waf" {
  source     = "../waf"
  depends_on = [module.s3]

  alb_names               = var.alb_names
  disabled_rules          = var.disabled_rules
  environment             = var.environment
  region                  = var.region
  protection_rules        = var.protection_rules
  waf_log_destination_arn = module.s3.waf_logs_destination_arn
}