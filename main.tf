resource "aws_s3_bucket_policy" "allow_replication" {
  bucket = "bsw-siem-cloudtrail"

  provider = aws.security

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for env_key, env in local.environments : {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${env.account_id}:role/waf-log-replication-role-${env_key}"
        }
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:PutObjectTagging"
        ]
        Resource = "arn:aws:s3:::bsw-siem-cloudtrail/AWSLogs/${env.account_id}/WAFLogs/*"
      }
    ]
  })
}

module "waf_wrapper_security_us_east_1" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.security
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["security-prod-us-east-1"].alb_names
  api_gateway_ids             = local.environments["security-prod-us-east-1"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["security-prod-us-east-1"].cloudfront_distribution_ids
  disabled_rules              = local.environments["security-prod-us-east-1"].disabled_rules
  environment                 = "security-prod-us-east-1"
  global                      = local.environments["security-prod-us-east-1"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-cloudtrail"
  protection_rules            = local.environments["security-prod-us-east-1"].protection_rules
}

module "waf_wrapper_security_global" {
  source = "./modules/waf-wrapper"

  providers = {
    aws = aws.security
  }

  # Key = environments/<subpath>/<filename>
  alb_names                   = local.environments["security-prod-global"].alb_names
  api_gateway_ids             = local.environments["security-prod-global"].api_gateway_ids
  cloudfront_distribution_ids = local.environments["security-prod-global"].cloudfront_distribution_ids
  disabled_rules              = local.environments["security-prod-global"].disabled_rules
  environment                 = "security-prod-global"
  global                      = local.environments["security-prod-global"].global
  log_forward_destination     = "arn:aws:s3:::bsw-siem-cloudtrail"
  protection_rules            = local.environments["security-prod-global"].protection_rules
}