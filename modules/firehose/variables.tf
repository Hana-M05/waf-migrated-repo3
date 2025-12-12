variable "firehose_name" {
  description = "Name of the Kinesis Firehose delivery stream"
  type        = string
}

variable "firehose_role_arn" {
  description = "ARN of the IAM role used by Firehose"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Firehose to deliver logs to"
  type        = string
}

variable "s3_prefix" {
  description = "S3 prefix for delivered logs"
  type        = string
}