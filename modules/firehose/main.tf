# Kinesis Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  name        = var.firehose_name
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = var.firehose_role_arn
    bucket_arn = var.s3_bucket_arn
    prefix     = var.s3_prefix

    compression_format = "GZIP"

    s3_backup_mode = var.s3_backup_bucket_arn != null ? "Enabled" : "Disabled"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_logs.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_logs.name
    }

    # Optional Lambda processor — omit lambda_processor_arn to disable.
    # When enabled, the Lambda receives every record before S3 delivery.
    # The Lambda must return all records unchanged (result = "Ok").
    dynamic "processing_configuration" {
      for_each = var.lambda_processor_arn != null ? [1] : []
      content {
        enabled = true
        processors {
          type = "Lambda"
          parameters {
            parameter_name  = "LambdaArn"
            parameter_value = var.lambda_processor_arn
          }
        }
      }
    }

    # Optional S3 backup — simultaneously writes ALL records to a second bucket.
    # Useful for keeping a raw copy in the product account while primary delivery
    # goes to the ob1 alloy bucket. NOTE: once enabled this cannot be disabled
    # without recreating the Firehose stream.
    dynamic "s3_backup_configuration" {
      for_each = var.s3_backup_bucket_arn != null ? [1] : []
      content {
        role_arn   = var.firehose_role_arn
        bucket_arn = var.s3_backup_bucket_arn
        prefix     = var.s3_prefix

        compression_format = "GZIP"

        cloudwatch_logging_options {
          enabled         = true
          log_group_name  = aws_cloudwatch_log_group.firehose_logs.name
          log_stream_name = aws_cloudwatch_log_stream.firehose_logs.name
        }
      }
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
