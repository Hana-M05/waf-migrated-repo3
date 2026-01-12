provider "aws" {
  alias  = "evm_dev_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::993748385324:role/WAF_Provisioner"
  }
}

provider "aws" {
  alias  = "evm_prod_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::622913004475:role/WAF_Provisioner"
  }
}


#########################################################################
########################### Firehose IAM Role ###########################
#########################################################################
module "firehose_role_policy_evm_dev" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.evm_dev_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

module "firehose_role_policy_evm_prod" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.evm_prod_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

#########################################################################
########################### EVM Dev Modules #############################
#########################################################################

module "waf_wrapper_evm_dev_us_east_1" {
  depends_on = [ module.firehose_role_policy_evm_dev ]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.evm_dev_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                    = local.environments["evm-dev-us-east-1"].alb_arns
  api_gateway_ids             = local.environments["evm-dev-us-east-1"].api_gateway_ids
  disabled_rules              = local.environments["evm-dev-us-east-1"].disabled_rules
  environment                 = "evm-dev-us-east-1"
  firehose_destination        = local.alloy_s3_buckets[local.environments["evm-dev-us-east-1"].region]
  firehose_role_arn           = module.firehose_role_policy_evm_dev.firehose_role_arn
  global                      = local.environments["evm-dev-us-east-1"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["evm-dev-us-east-1"].protection_rules
}

#########################################################################
########################### EVM Prod Modules ############################
#########################################################################

module "waf_wrapper_evm_prod_us_east_1" {
  depends_on = [ module.firehose_role_policy_evm_prod ]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.evm_prod_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                    = local.environments["evm-prod-us-east-1"].alb_arns
  api_gateway_ids             = local.environments["evm-prod-us-east-1"].api_gateway_ids
  disabled_rules              = local.environments["evm-prod-us-east-1"].disabled_rules
  environment                 = "evm-prod-us-east-1"
  firehose_destination        = local.alloy_s3_buckets[local.environments["evm-prod-us-east-1"].region]
  firehose_role_arn           = module.firehose_role_policy_evm_prod.firehose_role_arn
  global                      = local.environments["evm-prod-us-east-1"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["evm-prod-us-east-1"].protection_rules
}