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
