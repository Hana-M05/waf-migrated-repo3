module "waf_wrapper_security" {
  source = "./modules/waf-wrapper"
  
  providers = {
    aws = aws.security
  }

  # Key = environments/<subpath>/<filename>
  alb_names        = local.environments["security-security"].alb_names
  disabled_rules   = local.environments["security-security"].disabled_rules
  environment      = local.environments["security-security"].environment
  product          = local.environments["security-security"].product
  region           = local.environments["security-security"].region
  protection_rules = local.environments["security-security"].protection_rules
}