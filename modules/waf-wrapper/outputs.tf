output "replication_role_arn" {
  description = "The ARN of the replication role."
  value       = module.s3.replication_role_arn
}