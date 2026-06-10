##########################################################################
######################### Classic Dev Providers ##########################
##########################################################################
provider "aws" {
  alias  = "classic_dev_us_east_2"
  region = "us-east-2"
  assume_role {
    role_arn = "arn:aws:iam::881226391216:role/WAF_Provisioner"
  }
}


###########################################################################
########################## Classic Prod Providers #########################
###########################################################################
provider "aws" {
  alias  = "classic_prod_us_east_2"
  region = "us-east-2"
  assume_role {
    role_arn = "arn:aws:iam::989263075007:role/WAF_Provisioner"
  }
}

#########################################################################
########################### Firehose IAM Role ###########################
#########################################################################
module "firehose_role_policy_classic_dev" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.classic_dev_us_east_2
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

module "firehose_role_policy_classic_prod" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.classic_prod_us_east_2
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

########################################################################
######################### Classic Dev Modules ##########################
########################################################################
module "waf_wrapper_classic_dev_us_east_2" {
  depends_on = [module.firehose_role_policy_classic_dev]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.classic_dev_us_east_2
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                    = local.environments["classic-dev-us-east-2"].alb_arns
  api_gateway_ids             = local.environments["classic-dev-us-east-2"].api_gateway_ids
  disabled_rules              = local.environments["classic-dev-us-east-2"].disabled_rules
  environment                 = "classic-dev-us-east-2"
  firehose_destination        = local.alloy_s3_buckets[local.environments["classic-dev-us-east-2"].region]
  firehose_role_arn           = module.firehose_role_policy_classic_dev.firehose_role_arn
  global                      = local.environments["classic-dev-us-east-2"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["classic-dev-us-east-2"].protection_rules
  redacted_headers            = local.environments["classic-dev-us-east-2"].redacted_headers
  waf_error_subscribers       = local.environments["classic-dev-us-east-2"].waf_error_subscribers
}

#########################################################################
######################### Classic Prod Modules ##########################
#########################################################################
module "waf_wrapper_classic_staging_us_east_2" {
  depends_on = [module.firehose_role_policy_classic_prod]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.classic_prod_us_east_2
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                    = local.environments["classic-staging-us-east-2"].alb_arns
  api_gateway_ids             = local.environments["classic-staging-us-east-2"].api_gateway_ids
  disabled_rules              = local.environments["classic-staging-us-east-2"].disabled_rules
  environment                 = "classic-staging-us-east-2"
  firehose_destination        = local.alloy_s3_buckets[local.environments["classic-staging-us-east-2"].region]
  firehose_role_arn           = module.firehose_role_policy_classic_prod.firehose_role_arn
  global                      = local.environments["classic-staging-us-east-2"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["classic-staging-us-east-2"].protection_rules
  redacted_headers            = local.environments["classic-staging-us-east-2"].redacted_headers
  waf_error_subscribers       = local.environments["classic-staging-us-east-2"].waf_error_subscribers
}

module "waf_wrapper_classic_prod_us_east_2" {
  depends_on = [module.firehose_role_policy_classic_prod]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.classic_prod_us_east_2
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                   = local.environments["classic-prod-us-east-2"].alb_arns
  api_gateway_ids             = local.environments["classic-prod-us-east-2"].api_gateway_ids
  disabled_rules              = local.environments["classic-prod-us-east-2"].disabled_rules
  environment                 = "classic-prod-us-east-2"
  firehose_destination        = local.alloy_s3_buckets[local.environments["classic-prod-us-east-2"].region]
  firehose_role_arn           = module.firehose_role_policy_classic_prod.firehose_role_arn
  global                      = local.environments["classic-prod-us-east-2"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["classic-prod-us-east-2"].protection_rules
  redacted_headers            = local.environments["classic-prod-us-east-2"].redacted_headers
  waf_error_subscribers       = local.environments["classic-prod-us-east-2"].waf_error_subscribers
}

module "waf_wrapper_classic_schooldude_prod_us_east_2" {
  depends_on = [module.firehose_role_policy_classic_prod]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.classic_prod_us_east_2
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                    = local.environments["classic-schooldude-prod-us-east-2"].alb_arns
  api_gateway_ids             = local.environments["classic-schooldude-prod-us-east-2"].api_gateway_ids
  disabled_rules              = local.environments["classic-schooldude-prod-us-east-2"].disabled_rules
  environment                 = "classic-schooldude-prod-us-east-2"
  firehose_destination        = local.alloy_s3_buckets[local.environments["classic-schooldude-prod-us-east-2"].region]
  firehose_role_arn           = module.firehose_role_policy_classic_prod.firehose_role_arn
  global                      = local.environments["classic-schooldude-prod-us-east-2"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["classic-schooldude-prod-us-east-2"].protection_rules
  redacted_headers            = local.environments["classic-schooldude-prod-us-east-2"].redacted_headers
  waf_error_subscribers       = local.environments["classic-schooldude-prod-us-east-2"].waf_error_subscribers
}
