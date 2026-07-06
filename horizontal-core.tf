provider "aws" {
  alias  = "horizontal_core_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::973759413841:role/WAF_Provisioner"
  }
}

#########################################################################
########################### Firehose IAM Role ###########################
#########################################################################

module "firehose_role_policy_horizontal_core" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.horizontal_core_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

# #######################################################################################
# ########################### Horizontal Core Live Modules ##############################
# #######################################################################################
module "waf_wrapper_horizontal_core_dev_global" {
  depends_on = [ module.firehose_role_policy_horizontal_core ]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.horizontal_core_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                    = local.environments["horizontal-core-dev-global"].alb_arns
  api_gateway_ids             = local.environments["horizontal-core-dev-global"].api_gateway_ids
  disabled_rules              = local.environments["horizontal-core-dev-global"].disabled_rules
  environment                 = "horizontal-core-dev-global"
  firehose_destination        = local.alloy_s3_buckets[local.environments["horizontal-core-dev-global"].region]
  firehose_role_arn           = module.firehose_role_policy_horizontal_core.firehose_role_arn
  global                      = local.environments["horizontal-core-dev-global"].global
  protection_rules            = local.environments["horizontal-core-dev-global"].protection_rules
  redacted_headers            = local.environments["horizontal-core-dev-global"].redacted_headers
  waf_error_subscribers       = local.environments["horizontal-core-dev-global"].waf_error_subscribers
}

module "waf_wrapper_horizontal_core_staging_global" {
  depends_on = [ module.firehose_role_policy_horizontal_core ]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.horizontal_core_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                    = local.environments["horizontal-core-staging-global"].alb_arns
  api_gateway_ids             = local.environments["horizontal-core-staging-global"].api_gateway_ids
  disabled_rules              = local.environments["horizontal-core-staging-global"].disabled_rules
  environment                 = "horizontal-core-staging-global"
  firehose_destination        = local.alloy_s3_buckets[local.environments["horizontal-core-staging-global"].region]
  firehose_role_arn           = module.firehose_role_policy_horizontal_core.firehose_role_arn
  global                      = local.environments["horizontal-core-staging-global"].global
  protection_rules            = local.environments["horizontal-core-staging-global"].protection_rules
  redacted_headers            = local.environments["horizontal-core-staging-global"].redacted_headers
  waf_error_subscribers       = local.environments["horizontal-core-staging-global"].waf_error_subscribers
}

module "waf_wrapper_horizontal_core_prod_global" {
  depends_on = [ module.firehose_role_policy_horizontal_core ]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.horizontal_core_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                    = local.environments["horizontal-core-prod-global"].alb_arns
  api_gateway_ids             = local.environments["horizontal-core-prod-global"].api_gateway_ids
  disabled_rules              = local.environments["horizontal-core-prod-global"].disabled_rules
  environment                 = "horizontal-core-prod-global"
  firehose_destination        = local.alloy_s3_buckets[local.environments["horizontal-core-prod-global"].region]
  firehose_role_arn           = module.firehose_role_policy_horizontal_core.firehose_role_arn
  global                      = local.environments["horizontal-core-prod-global"].global
  protection_rules            = local.environments["horizontal-core-prod-global"].protection_rules
  redacted_headers            = local.environments["horizontal-core-prod-global"].redacted_headers
  waf_error_subscribers       = local.environments["horizontal-core-prod-global"].waf_error_subscribers
}
