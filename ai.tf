##########################################################################
############################ AI Dev Providers ############################
##########################################################################
provider "aws" {
  alias  = "ai_dev_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::379262058790:role/WAF_Provisioner"
  }
}


###########################################################################
############################ AI Prod Providers ############################
###########################################################################
provider "aws" {
  alias  = "ai_prod_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::434927109356:role/WAF_Provisioner"
  }
}


#########################################################################
########################### Firehose IAM Role ###########################
#########################################################################
module "firehose_role_policy_ai_dev" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.ai_dev_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

module "firehose_role_policy_ai_prod" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.ai_prod_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

########################################################################
############################ AI Dev Modules ############################
########################################################################
module "waf_wrapper_ai_dev_us_east_1" {
  depends_on = [module.firehose_role_policy_ai_dev]
  source     = "./modules/waf-wrapper"

  providers = {
    aws = aws.ai_dev_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                = local.environments["ai-dev-us-east-1"].alb_arns
  api_gateway_ids         = local.environments["ai-dev-us-east-1"].api_gateway_ids
  disabled_rules          = local.environments["ai-dev-us-east-1"].disabled_rules
  environment             = "ai-dev-us-east-1"
  firehose_destination    = local.alloy_s3_buckets[local.environments["ai-dev-us-east-1"].region]
  firehose_role_arn       = module.firehose_role_policy_ai_dev.firehose_role_arn
  global                  = local.environments["ai-dev-us-east-1"].global
  log_forward_destination = "arn:aws:s3:::bsw-siem-waf"
  protection_rules        = local.environments["ai-dev-us-east-1"].protection_rules
  redacted_headers        = local.environments["ai-dev-us-east-1"].redacted_headers
  waf_error_subscribers   = local.environments["ai-dev-us-east-1"].waf_error_subscribers
}

#########################################################################
############################ AI Prod Modules ############################
#########################################################################

module "waf_wrapper_ai_prod_us_east_1" {
  depends_on = [module.firehose_role_policy_ai_prod]
  source     = "./modules/waf-wrapper"

  providers = {
    aws = aws.ai_prod_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                = local.environments["ai-prod-us-east-1"].alb_arns
  api_gateway_ids         = local.environments["ai-prod-us-east-1"].api_gateway_ids
  disabled_rules          = local.environments["ai-prod-us-east-1"].disabled_rules
  environment             = "ai-prod-us-east-1"
  firehose_destination    = local.alloy_s3_buckets[local.environments["ai-prod-us-east-1"].region]
  firehose_role_arn       = module.firehose_role_policy_ai_prod.firehose_role_arn
  global                  = local.environments["ai-prod-us-east-1"].global
  log_forward_destination = "arn:aws:s3:::bsw-siem-waf"
  protection_rules        = local.environments["ai-prod-us-east-1"].protection_rules
  redacted_headers        = local.environments["ai-prod-us-east-1"].redacted_headers
  waf_error_subscribers   = local.environments["ai-prod-us-east-1"].waf_error_subscribers
}
