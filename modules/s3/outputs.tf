output "waf_logs_destination_arn" {
  description = "The ARN of the S3 bucket used for WAF logs"
  value       = aws_s3_bucket.waf_logs.arn
}