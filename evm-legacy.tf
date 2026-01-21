provider "aws" {
  alias  = "evm_legacy_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::290431122157:role/WAF_Provisioner"
  }
}


#########################################################################
########################### Firehose IAM Role ###########################
#########################################################################
module "firehose_role_policy_evm_legacy" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.evm_legacy_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

#########################################################################
######################### EVM Legacy Modules ############################
#########################################################################

module "waf_wrapper_evm_legacy_cloudfront" {
  depends_on = [module.firehose_role_policy_evm_legacy]
  source     = "./modules/waf-wrapper"

  providers = {
    aws = aws.evm_legacy_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                = local.environments["evm-legacy-event-manager-surveys"].alb_arns
  api_gateway_ids         = local.environments["evm-legacy-event-manager-surveys"].api_gateway_ids
  disabled_rules          = local.environments["evm-legacy-event-manager-surveys"].disabled_rules
  environment             = "evm-legacy-event-manager-surveys"
  firehose_destination    = local.alloy_s3_buckets[local.environments["evm-legacy-event-manager-surveys"].region]
  firehose_role_arn       = module.firehose_role_policy_evm_legacy.firehose_role_arn
  global                  = local.environments["evm-legacy-event-manager-surveys"].global
  log_forward_destination = "arn:aws:s3:::bsw-siem-waf"
  protection_rules        = local.environments["evm-legacy-event-manager-surveys"].protection_rules
  waf_error_subscribers   = local.environments["evm-legacy-event-manager-surveys"].waf_error_subscribers
}