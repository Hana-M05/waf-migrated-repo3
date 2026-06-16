variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs that Firehose should have access to"
  type        = list(string)
}

variable "lambda_processor_arn" {
  description = "ARN of the Lambda processor that Firehose is allowed to invoke. Set to null if not using a processor."
  type        = string
  default     = null
}
