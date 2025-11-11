###############################################################
############### Confirm Dev Regional Providers ################
###############################################################
provider "aws" {
  alias  = "devops_internal_tools_prod_helpsite"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::841502009442:role/WAF_Provisioner"
  }
}

module "waf_wrapper_devops_internal_tools_prod_helpsite" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.devops_internal_tools_prod_helpsite
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["devops-internal-tools-prod-helpsite"].alb_names
  api_gateway_ids             = local.environments["devops-internal-tools-prod-helpsite"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["devops-internal-tools-prod-helpsite"].cloudfront_distribution_ids
  disabled_rules              = local.environments["devops-internal-tools-prod-helpsite"].disabled_rules
  environment                 = "prod-helpsite"
  global                      = local.environments["devops-internal-tools-prod-helpsite"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["devops-internal-tools-prod-helpsite"].protection_rules
}