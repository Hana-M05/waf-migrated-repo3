output "waf_logs_destination_arn" {
  description = "The ARN of the S3 bucket used for WAF logs"
  value       = aws_s3_bucket.waf_logs.arn
}

output "replication_role_arn" {
  description = "The ARN of the IAM role used for S3 replication"
  value       = aws_iam_role.s3_replication.arn
}