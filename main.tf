module "waf_wrapper_security" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.security
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["security-security"].alb_names
  api_gateway_ids             = local.environments["security-security"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["security-security"].cloudfront_distribution_ids
  disabled_rules              = local.environments["security-security"].disabled_rules
  environment                 = local.environments["security-security"].environment
  region                      = local.environments["security-security"].region
  protection_rules            = local.environments["security-security"].protection_rules
}