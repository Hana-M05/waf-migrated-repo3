# Kinesis Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  name        = var.firehose_name
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = var.firehose_role_arn
    bucket_arn = var.s3_bucket_arn
    prefix     = var.s3_prefix

    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_logs.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_logs.name
    }
  }

}

# CloudWatch log group for Firehose
resource "aws_cloudwatch_log_group" "firehose_logs" {
  name              = "/aws/kinesisfirehose/${var.firehose_name}"
  retention_in_days = 7

}

# CloudWatch log stream for Firehose
resource "aws_cloudwatch_log_stream" "firehose_logs" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose_logs.name
}
