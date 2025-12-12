output "firehose_arn" {
  description = "ARN of the Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.waf_logs.arn
}