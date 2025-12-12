variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs that Firehose should have access to"
  type        = list(string)
}
