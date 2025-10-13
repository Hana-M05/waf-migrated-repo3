module "waf_wrapper_security_us_east_1" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.security
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["security-prod-us-east-1"].alb_names
  api_gateway_ids             = local.environments["security-prod-us-east-1"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["security-prod-us-east-1"].cloudfront_distribution_ids
  disabled_rules              = local.environments["security-prod-us-east-1"].disabled_rules
  environment                 = "prod-us-east-1"
  global                      = local.environments["security-prod-us-east-1"].global
  region                      = local.environments["security-prod-us-east-1"].region
  protection_rules            = local.environments["security-prod-us-east-1"].protection_rules
}

module "waf_wrapper_security_global" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.security
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["security-prod-global"].alb_names
  api_gateway_ids             = local.environments["security-prod-global"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["security-prod-global"].cloudfront_distribution_ids
  disabled_rules              = local.environments["security-prod-global"].disabled_rules
  environment                 = "prod-global"
  global                      = local.environments["security-prod-global"].global
  region                      = local.environments["security-prod-global"].region
  protection_rules            = local.environments["security-prod-global"].protection_rules
}