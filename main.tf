###############################################################################
##### Temp S3 Bucket to allow WAF log replication to Security #####
###############################################################################
module "elastic_waf_destination" {
  source = "./modules/elastic-waf-destination"

  providers = {
    aws = aws.security
  }

  replication_roles = [
    module.waf_wrapper_security_us_east_1.replication_role_arn,
    module.waf_wrapper_security_global.replication_role_arn,
    module.waf_wrapper_confirm_dev_ap_south_1.replication_role_arn,
    module.waf_wrapper_confirm_dev_ap_southeast_2.replication_role_arn,
    module.waf_wrapper_confirm_dev_eu_west_2.replication_role_arn,
    module.waf_wrapper_asset_essentials_dev_us_east_1.replication_role_arn,
    module.waf_wrapper_evm_legacy_cloudfront.replication_role_arn,
  ]
}
###############################################################################