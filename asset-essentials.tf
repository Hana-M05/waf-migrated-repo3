##########################################################################
##################### Asset Essentials Dev Providers #####################
##########################################################################
provider "aws" {
  alias  = "asset_essentials_dev_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::750920731536:role/WAF_Provisioner"
  }
}

###########################################################################
##################### Asset Essentials Prod Providers #####################
###########################################################################
provider "aws" {
  alias  = "asset_essentials_prod_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::748037917842:role/WAF_Provisioner"
  }
}

provider "aws" {
  alias  = "asset_essentials_prod_eu_west_2"
  region = "eu-west-2"
  assume_role {
    role_arn = "arn:aws:iam::748037917842:role/WAF_Provisioner"
  }
}

provider "aws" {
  alias  = "asset_essentials_prod_ca_central_1"
  region = "ca-central-1"
  assume_role {
    role_arn = "arn:aws:iam::748037917842:role/WAF_Provisioner"
  }
}

########################################################################
##################### Asset Essentials Dev Modules #####################
########################################################################
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

#########################################################################
##################### Asset Essentials Prod Modules #####################
#########################################################################
module "waf_wrapper_asset_essentials_prod_us_east_1" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.asset_essentials_prod_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["asset-essentials-prod-us-east-1"].alb_names
  api_gateway_ids             = local.environments["asset-essentials-prod-us-east-1"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["asset-essentials-prod-us-east-1"].cloudfront_distribution_ids
  disabled_rules              = local.environments["asset-essentials-prod-us-east-1"].disabled_rules
  environment                 = "asset-essentials-prod-us-east-1"
  global                      = local.environments["asset-essentials-prod-us-east-1"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["asset-essentials-prod-us-east-1"].protection_rules
}

module "waf_wrapper_asset_essentials_prod_eu_west_2" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.asset_essentials_prod_eu_west_2
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["asset-essentials-prod-eu-west-2"].alb_names
  api_gateway_ids             = local.environments["asset-essentials-prod-eu-west-2"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["asset-essentials-prod-eu-west-2"].cloudfront_distribution_ids
  disabled_rules              = local.environments["asset-essentials-prod-eu-west-2"].disabled_rules
  environment                 = "asset-essentials-prod-eu-west-2"
  global                      = local.environments["asset-essentials-prod-eu-west-2"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["asset-essentials-prod-eu-west-2"].protection_rules
}

module "waf_wrapper_asset_essentials_prod_ca_central_1" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.asset_essentials_prod_ca_central_1
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["asset-essentials-prod-ca-central-1"].alb_names
  api_gateway_ids             = local.environments["asset-essentials-prod-ca-central-1"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["asset-essentials-prod-ca-central-1"].cloudfront_distribution_ids
  disabled_rules              = local.environments["asset-essentials-prod-ca-central-1"].disabled_rules
  environment                 = "asset-essentials-prod-ca-1"
  global                      = local.environments["asset-essentials-prod-ca-central-1"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["asset-essentials-prod-ca-central-1"].protection_rules
}