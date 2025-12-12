data "aws_caller_identity" "current" {}

module "firehose" {
  source = "../firehose"

  firehose_name          = "aws-waf-logs-firehose-${var.environment}"
  firehose_role_arn      = var.firehose_role_arn
  s3_bucket_arn          = var.firehose_destination
  s3_prefix              = "AWSLogs/${data.aws_caller_identity.current.account_id}/WAFLogs/"
}

module "waf" {
  source     = "../waf"
  depends_on = [module.firehose]

  alb_arns                   = var.alb_arns
  api_gateway_ids             = var.api_gateway_ids
  disabled_rules              = var.disabled_rules
  environment                 = var.environment
  global                      = var.global
  protection_rules            = var.protection_rules
  waf_log_destination_arn     = module.firehose.firehose_arn
}