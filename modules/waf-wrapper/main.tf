module "s3" {
  source = "../s3"

  environment             = var.environment
  log_forward_destination = var.log_forward_destination
}

module "waf" {
  source     = "../waf"
  depends_on = [module.s3]

  alb_names                   = var.alb_names
  api_gateway_ids             = var.api_gateway_ids
  disabled_rules              = var.disabled_rules
  environment                 = var.environment
  global                      = var.global
  protection_rules            = var.protection_rules
  waf_log_destination_arn     = module.s3.waf_logs_destination_arn
}