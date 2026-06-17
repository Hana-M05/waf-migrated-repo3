data "aws_caller_identity" "current" {}

module "firehose" {
  source = "../firehose"

  firehose_name        = "aws-waf-logs-firehose-${var.environment}"
  firehose_role_arn    = var.firehose_role_arn
  s3_bucket_arn        = var.firehose_destination
  s3_prefix            = "AWSLogs/${data.aws_caller_identity.current.account_id}/WAFLogs/"
  lambda_processor_arn = var.lambda_processor_arn
  s3_backup_bucket_arn = var.s3_backup_bucket_arn
}

module "waf" {
  source     = "../waf"
  depends_on = [module.firehose]

  alb_arns                = var.alb_arns
  api_gateway_ids         = var.api_gateway_ids
  disabled_rules          = var.disabled_rules
  environment             = var.environment
  global                  = var.global
  protection_rules        = var.protection_rules
  redacted_headers        = var.redacted_headers
  waf_error_subscribers   = var.waf_error_subscribers
  waf_log_destination_arn = module.firehose.firehose_arn
}