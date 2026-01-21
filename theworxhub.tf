##########################################################################
######################## TheWorxHub Dev Providers ########################
##########################################################################
provider "aws" {
  alias  = "theworxhub_dev_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::910562428656:role/WAF_Provisioner"
  }
}

##########################################################################
####################### TheWorxHub Prod Providers ########################
##########################################################################
provider "aws" {
  alias  = "theworxhub_prod_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::499436724538:role/WAF_Provisioner"
  }
}


#########################################################################
########################### Firehose IAM Role ###########################
#########################################################################
module "firehose_role_policy_theworxhub_dev" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.theworxhub_dev_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

module "firehose_role_policy_theworxhub_prod" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.theworxhub_prod_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

##########################################################################
######################### TheWorxHub Dev Modules #########################
##########################################################################
module "waf_wrapper_theworxhub_dev_us_east_1" {
  depends_on = [module.firehose_role_policy_theworxhub_dev]
  source     = "./modules/waf-wrapper"

  providers = {
    aws = aws.theworxhub_dev_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                = local.environments["theworxhub-dev-us-east-1"].alb_arns
  api_gateway_ids         = local.environments["theworxhub-dev-us-east-1"].api_gateway_ids
  disabled_rules          = local.environments["theworxhub-dev-us-east-1"].disabled_rules
  environment             = "theworxhub-dev-us-east-1"
  firehose_destination    = local.alloy_s3_buckets[local.environments["theworxhub-dev-us-east-1"].region]
  firehose_role_arn       = module.firehose_role_policy_theworxhub_dev.firehose_role_arn
  global                  = local.environments["theworxhub-dev-us-east-1"].global
  log_forward_destination = "arn:aws:s3:::bsw-siem-waf"
  protection_rules        = local.environments["theworxhub-dev-us-east-1"].protection_rules
  waf_error_subscribers   = local.environments["theworxhub-dev-us-east-1"].waf_error_subscribers
}

###########################################################################
######################### TheWorxHub Prod Modules #########################
###########################################################################
module "waf_wrapper_theworxhub_prod_us_east_1" {
  depends_on = [module.firehose_role_policy_theworxhub_prod]
  source     = "./modules/waf-wrapper"

  providers = {
    aws = aws.theworxhub_prod_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                = local.environments["theworxhub-prod-us-east-1"].alb_arns
  api_gateway_ids         = local.environments["theworxhub-prod-us-east-1"].api_gateway_ids
  disabled_rules          = local.environments["theworxhub-prod-us-east-1"].disabled_rules
  environment             = "theworxhub-prod-us-east-1"
  firehose_destination    = local.alloy_s3_buckets[local.environments["theworxhub-prod-us-east-1"].region]
  firehose_role_arn       = module.firehose_role_policy_theworxhub_prod.firehose_role_arn
  global                  = local.environments["theworxhub-prod-us-east-1"].global
  log_forward_destination = "arn:aws:s3:::bsw-siem-waf"
  protection_rules        = local.environments["theworxhub-prod-us-east-1"].protection_rules
  waf_error_subscribers   = local.environments["theworxhub-prod-us-east-1"].waf_error_subscribers
}