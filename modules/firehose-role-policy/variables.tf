variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs that Firehose should have access to"
  type        = list(string)
}

variable "lambda_processor_arn" {
  description = "ARN of the Lambda processor that Firehose is allowed to invoke. Required when enable_lambda_processor = true."
  type        = string
  default     = null
}

variable "enable_lambda_processor" {
  description = "Set to true to create the Lambda invoke policy on the Firehose role. Must be a static bool (not computed) to avoid plan-time errors."
  type        = bool
  default     = false
}
