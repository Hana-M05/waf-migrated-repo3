output "firehose_role_arn" {
  description = "ARN of the IAM role used by Firehose"
  value       = aws_iam_role.firehose_role.arn
}