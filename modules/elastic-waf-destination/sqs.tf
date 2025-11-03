# Create the SQS queue
resource "aws_sqs_queue" "waf_logs_queue" {
  name                       = "waf-logs-queue"
  message_retention_seconds  = 259200 # Retain messages for 3 days
  visibility_timeout_seconds = 910
}

# Create the SQS queue policy to allow S3 to send messages
resource "aws_sqs_queue_policy" "waf_logs_queue_policy" {
  queue_url = aws_sqs_queue.waf_logs_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.waf_logs_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.waf-bucket.arn
          }
        }
      }
    ]
  })
}

# Configure S3 bucket notifications to send events to the SQS queue
resource "aws_s3_bucket_notification" "waf_bucket_notifications" {
  bucket = aws_s3_bucket.waf-bucket.id

  queue {
    queue_arn = aws_sqs_queue.waf_logs_queue.arn
    events    = ["s3:ObjectCreated:*"] # Trigger on object creation
  }
}