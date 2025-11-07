provider "aws" {
  alias  = "security"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::533267359674:role/WAF_Provisioner"
  }
}

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
  environment                 = "security-prod-us-east-1"
  global                      = local.environments["security-prod-us-east-1"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
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
  environment                 = "security-prod-global"
  global                      = local.environments["security-prod-global"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["security-prod-global"].protection_rules
}