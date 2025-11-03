###############################################################################
##### Temp S3 Bucket to allow WAF log replication to Security #####
###############################################################################
module "elastic_waf_destination" {
  source = "./modules/elastic-waf-destination"

  providers = {
    aws = aws.security
  }

  replication_roles = [
    module.waf_wrapper_security_us_east_1.replication_role_arn,
    module.waf_wrapper_security_global.replication_role_arn,
  ]
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