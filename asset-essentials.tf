provider "aws" {
  alias = "asset_essentials_dev_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::750920731536:role/WAF_Provisioner"
  }
}

module "waf_wrapper_asset_essentials_dev_us_east_1" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.asset_essentials_dev_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["asset-essentials-dev-us-east-1"].alb_names
  api_gateway_ids             = local.environments["asset-essentials-dev-us-east-1"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["asset-essentials-dev-us-east-1"].cloudfront_distribution_ids
  disabled_rules              = local.environments["asset-essentials-dev-us-east-1"].disabled_rules
  environment                 = "asset-essentials-dev-us-east-1"
  global                      = local.environments["asset-essentials-dev-us-east-1"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["asset-essentials-dev-us-east-1"].protection_rules
}