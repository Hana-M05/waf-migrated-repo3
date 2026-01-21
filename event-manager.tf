provider "aws" {
  alias  = "event_manager_dev_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::993748385324:role/WAF_Provisioner"
  }
}

provider "aws" {
  alias  = "event_manager_prod_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::622913004475:role/WAF_Provisioner"
  }
}


#########################################################################
########################### Firehose IAM Role ###########################
#########################################################################
module "firehose_role_policy_event_manager_dev" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.event_manager_dev_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

module "firehose_role_policy_event_manager_prod" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.event_manager_prod_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

#########################################################################
########################### EVM Dev Modules #############################
#########################################################################

module "waf_wrapper_event_manager_dev_us_east_1" {
  depends_on = [ module.firehose_role_policy_event_manager_dev ]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.event_manager_dev_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                    = local.environments["event-manager-dev-us-east-1"].alb_arns
  api_gateway_ids             = local.environments["event-manager-dev-us-east-1"].api_gateway_ids
  disabled_rules              = local.environments["event-manager-dev-us-east-1"].disabled_rules
  environment                 = "event-manager-dev-us-east-1"
  firehose_destination        = local.alloy_s3_buckets[local.environments["event-manager-dev-us-east-1"].region]
  firehose_role_arn           = module.firehose_role_policy_event_manager_dev.firehose_role_arn
  global                      = local.environments["event-manager-dev-us-east-1"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["event-manager-dev-us-east-1"].protection_rules
  waf_error_subscribers       = local.environments["event-manager-dev-us-east-1"].waf_error_subscribers
}

#########################################################################
########################### EVM Prod Modules ############################
#########################################################################

module "waf_wrapper_event_manager_prod_us_east_1" {
  depends_on = [ module.firehose_role_policy_event_manager_prod ]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.event_manager_prod_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                    = local.environments["event-manager-prod-us-east-1"].alb_arns
  api_gateway_ids             = local.environments["event-manager-prod-us-east-1"].api_gateway_ids
  disabled_rules              = local.environments["event-manager-prod-us-east-1"].disabled_rules
  environment                 = "event-manager-prod-us-east-1"
  firehose_destination        = local.alloy_s3_buckets[local.environments["event-manager-prod-us-east-1"].region]
  firehose_role_arn           = module.firehose_role_policy_event_manager_prod.firehose_role_arn
  global                      = local.environments["event-manager-prod-us-east-1"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["event-manager-prod-us-east-1"].protection_rules
  waf_error_subscribers       = local.environments["event-manager-prod-us-east-1"].waf_error_subscribers
}