provider "aws" {
  alias  = "security"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::533267359674:role/WAF_Provisioner"
  }
}

#########################################################################
########################### Firehose IAM Role ###########################
#########################################################################
module "firehose_role_policy_security" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.security
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

# #########################################################################
# ################### WAF Notifications SNS Topic #########################
# #########################################################################
resource "aws_sns_topic_subscription" "security_waf_update_notifications" {
  for_each = toset(local.waf_update_monitors)

  provider  = aws.security
  topic_arn = "arn:aws:sns:us-east-1:849524154584:AWS-WAFV2-Managed-Rule-Set-Updates"
  protocol  = "email"
  endpoint  = each.value
}

#########################################################################
######################### Security Prod Modules #########################
#########################################################################
module "waf_wrapper_security_us_east_1" {
  depends_on = [module.firehose_role_policy_security]
  source     = "./modules/waf-wrapper"

  providers = {
    aws = aws.security
  }

  alb_arns                = local.environments["security-prod-us-east-1"].alb_arns
  api_gateway_ids         = local.environments["security-prod-us-east-1"].api_gateway_ids
  disabled_rules          = local.environments["security-prod-us-east-1"].disabled_rules
  environment             = "security-prod-us-east-1"
  firehose_destination    = local.alloy_s3_buckets[local.environments["security-prod-us-east-1"].region]
  firehose_role_arn       = module.firehose_role_policy_security.firehose_role_arn
  global                  = local.environments["security-prod-us-east-1"].global
  log_forward_destination = "arn:aws:s3:::bsw-siem-waf"
  protection_rules        = local.environments["security-prod-us-east-1"].protection_rules
}

module "waf_wrapper_security_global" {
  depends_on = [module.firehose_role_policy_security]
  source     = "./modules/waf-wrapper"

  providers = {
    aws = aws.security
  }

  alb_arns                = local.environments["security-prod-global"].alb_arns
  api_gateway_ids         = local.environments["security-prod-global"].api_gateway_ids
  disabled_rules          = local.environments["security-prod-global"].disabled_rules
  environment             = "security-prod-global"
  firehose_destination    = local.alloy_s3_buckets[local.environments["security-prod-global"].region]
  firehose_role_arn       = module.firehose_role_policy_security.firehose_role_arn
  global                  = local.environments["security-prod-global"].global
  log_forward_destination = "arn:aws:s3:::bsw-siem-waf"
  protection_rules        = local.environments["security-prod-global"].protection_rules
}