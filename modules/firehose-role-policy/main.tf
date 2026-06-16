# IAM role for Kinesis Firehose
resource "aws_iam_role" "firehose_role" {
  name     = "waf-log-firehose-delivery"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Firehose to write to S3
resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "waf-log-firehose-delivery-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = flatten([
          for bucket in var.s3_bucket_arns : [
            bucket,
            "${bucket}/*"
          ]
        ])
      }
    ]
  })
}

# Optional IAM policy granting Firehose permission to invoke the penalty-box Lambda.
# Only created when a Lambda ARN is supplied.
resource "aws_iam_role_policy" "firehose_lambda_policy" {
  count = var.lambda_processor_arn != null ? 1 : 0

  name = "waf-log-firehose-lambda-invoke-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = var.lambda_processor_arn
      }
    ]
  })
}