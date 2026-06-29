output "lambda_arn" {
  description = "ARN of the penalty-box Lambda function (used as Firehose processor)"
  value       = aws_lambda_function.penalty_box.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB penalty-box table"
  value       = aws_dynamodb_table.penalty_box.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB penalty-box table"
  value       = aws_dynamodb_table.penalty_box.arn
}

output "log_bucket_arn" {
  description = "ARN of the S3 bucket receiving Firehose log backups"
  value       = aws_s3_bucket.penalty_box_logs.arn
}

output "log_bucket_id" {
  description = "Name of the S3 bucket receiving Firehose log backups"
  value       = aws_s3_bucket.penalty_box_logs.id
}

output "known_good_ips_ssm_param" {
  description = "SSM parameter name for the known-good IP list (update to change CIDRs without redeploying Lambda)"
  value       = aws_ssm_parameter.known_good_ips.name
}

output "ip_set_arn" {
  description = "ARN of the WAFv2 penalty-box IP set (pass to waf-wrapper as penalty_box_ip_set_arn)"
  value       = aws_wafv2_ip_set.penalty_box.arn
}

output "ip_set_id" {
  description = "ID of the WAFv2 penalty-box IP set (used by the Lambda to call UpdateIPSet)"
  value       = aws_wafv2_ip_set.penalty_box.id
}
