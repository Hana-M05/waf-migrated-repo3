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

variable "lambda_processor_arn" {
  description = "ARN of the Lambda function to use as a Firehose record processor. Set to null to disable."
  type        = string
  default     = null
}

variable "s3_backup_bucket_arn" {
  description = "ARN of an S3 bucket to receive a backup of all records (S3BackupMode). Set to null to disable. WARNING: once enabled this cannot be turned off without recreating the stream."
  type        = string
  default     = null
}