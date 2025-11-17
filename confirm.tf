###############################################################
############### Confirm Dev Regional Providers ################
###############################################################
provider "aws" {
  alias  = "confirm_dev_ap_south_1"
  region = "ap-south-1"
  assume_role {
    role_arn = "arn:aws:iam::870519644306:role/WAF_Provisioner"
  }
}

provider "aws" {
  alias  = "confirm_dev_ap_southeast_2"
  region = "ap-southeast-2"
  assume_role {
    role_arn = "arn:aws:iam::870519644306:role/WAF_Provisioner"
  }
}

provider "aws" {
  alias  = "confirm_dev_eu_west_2"
  region = "eu-west-2"
  assume_role {
    role_arn = "arn:aws:iam::870519644306:role/WAF_Provisioner"
  }
}

################################################################
############### Confirm Prod Regional Providers ################
################################################################
provider "aws" {
  alias  = "confirm_aus_prod_ap_southeast_2"
  region = "ap-southeast-2"
  assume_role {
    role_arn = "arn:aws:iam::847014677591:role/WAF_Provisioner"
  }
}

provider "aws" {
  alias  = "confirm_uk_prod_eu_west_2"
  region = "eu-west-2"
  assume_role {
    role_arn = "arn:aws:iam::425444504751:role/WAF_Provisioner"
  }
}

provider "aws" {
  alias  = "confirm_uk_prod_us_east_2"
  region = "us-east-2"
  assume_role {
    role_arn = "arn:aws:iam::425444504751:role/WAF_Provisioner"
  }
}

###############################################################
##################### Confirm Dev Modules #####################
###############################################################

module "waf_wrapper_confirm_dev_ap_south_1" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.confirm_dev_ap_south_1
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["confirm-dev-ap-south-1"].alb_names
  api_gateway_ids             = local.environments["confirm-dev-ap-south-1"].api_gateway_ids
  disabled_rules              = local.environments["confirm-dev-ap-south-1"].disabled_rules
  environment                 = "confirm-dev-ap-south-1"
  global                      = local.environments["confirm-dev-ap-south-1"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["confirm-dev-ap-south-1"].protection_rules
}

module "waf_wrapper_confirm_dev_ap_southeast_2" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.confirm_dev_ap_southeast_2
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["confirm-dev-ap-southeast-2"].alb_names
  api_gateway_ids             = local.environments["confirm-dev-ap-southeast-2"].api_gateway_ids
  disabled_rules              = local.environments["confirm-dev-ap-southeast-2"].disabled_rules
  environment                 = "confirm-dev-ap-southeast-2"
  global                      = local.environments["confirm-dev-ap-southeast-2"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["confirm-dev-ap-southeast-2"].protection_rules
}

module "waf_wrapper_confirm_dev_eu_west_2" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.confirm_dev_eu_west_2
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["confirm-dev-eu-west-2"].alb_names
  api_gateway_ids             = local.environments["confirm-dev-eu-west-2"].api_gateway_ids
  disabled_rules              = local.environments["confirm-dev-eu-west-2"].disabled_rules
  environment                 = "confirm-dev-eu-west-2"
  global                      = local.environments["confirm-dev-eu-west-2"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["confirm-dev-eu-west-2"].protection_rules
}

################################################################
##################### Confirm Prod Modules #####################
################################################################
module "waf_wrapper_confirm_aus_prod_ap_southeast_2" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.confirm_aus_prod_ap_southeast_2
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["confirm-aus-prod-ap-southeast-2"].alb_names
  api_gateway_ids             = local.environments["confirm-aus-prod-ap-southeast-2"].api_gateway_ids
  disabled_rules              = local.environments["confirm-aus-prod-ap-southeast-2"].disabled_rules
  environment                 = "confirm-aus-prod-ap-southeast-2"
  global                      = local.environments["confirm-aus-prod-ap-southeast-2"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["confirm-aus-prod-ap-southeast-2"].protection_rules
}

module "waf_wrapper_confirm_uk_prod_eu_west_2" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.confirm_uk_prod_eu_west_2
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["confirm-uk-prod-eu-west-2"].alb_names
  api_gateway_ids             = local.environments["confirm-uk-prod-eu-west-2"].api_gateway_ids
  disabled_rules              = local.environments["confirm-uk-prod-eu-west-2"].disabled_rules
  environment                 = "confirm-uk-prod-eu-west-2"
  global                      = local.environments["confirm-uk-prod-eu-west-2"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["confirm-uk-prod-eu-west-2"].protection_rules
}

module "waf_wrapper_confirm_uk_prod_us_east_2" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.confirm_uk_prod_us_east_2
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["confirm-uk-prod-us-east-2"].alb_names
  api_gateway_ids             = local.environments["confirm-uk-prod-us-east-2"].api_gateway_ids
  disabled_rules              = local.environments["confirm-uk-prod-us-east-2"].disabled_rules
  environment                 = "confirm-uk-prod-us-east-2"
  global                      = local.environments["confirm-uk-prod-us-east-2"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["confirm-uk-prod-us-east-2"].protection_rules
}