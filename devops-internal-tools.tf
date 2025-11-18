###############################################################
########## DevOps Internal Tools Regional Providers ###########
###############################################################
provider "aws" {
  alias  = "devops_internal_tools_prod_helpsite"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::841502009442:role/WAF_Provisioner"
  }
}

#########################################################################
########################### Firehose IAM Role ###########################
#########################################################################
module "firehose_role_policy_devops_internal_tools" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.devops_internal_tools_prod_helpsite
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}
#########################################################################
##################### DevOps Internal Tools Modules ####################
#########################################################################

module "waf_wrapper_devops_internal_tools_prod_helpsite" {
  depends_on = [ module.firehose_role_policy_devops_internal_tools ]
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.devops_internal_tools_prod_helpsite
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["devops-internal-tools-prod-helpsite"].alb_names
  api_gateway_ids             = local.environments["devops-internal-tools-prod-helpsite"].api_gateway_ids
  disabled_rules              = local.environments["devops-internal-tools-prod-helpsite"].disabled_rules
  environment                 = "prod-helpsite"
  firehose_destination        = local.alloy_s3_buckets[local.environments["devops-internal-tools-prod-helpsite"].region]
  firehose_role_arn           = module.firehose_role_policy_devops_internal_tools.firehose_role_arn
  global                      = local.environments["devops-internal-tools-prod-helpsite"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["devops-internal-tools-prod-helpsite"].protection_rules
}