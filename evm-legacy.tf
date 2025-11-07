provider "aws" {
  alias = "evm_legacy_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::290431122157:role/WAF_Provisioner"
  }
}

module "waf_wrapper_evm_legacy_cloudfront" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.evm_legacy_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["evm-legacy-event-manager-surveys"].alb_names
  api_gateway_ids             = local.environments["evm-legacy-event-manager-surveys"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["evm-legacy-event-manager-surveys"].cloudfront_distribution_ids
  disabled_rules              = local.environments["evm-legacy-event-manager-surveys"].disabled_rules
  environment                 = "evm-legacy-event-manager-surveys"
  global                      = local.environments["evm-legacy-event-manager-surveys"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-waf"
  protection_rules            = local.environments["evm-legacy-event-manager-surveys"].protection_rules
}