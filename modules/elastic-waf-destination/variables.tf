variable "replication_roles" {
  description = "List of replication roles for the WAF destination."
  type        = list(string)
  default     = []
}