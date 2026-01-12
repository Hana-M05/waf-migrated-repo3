output "waf_acl_arn" {
  value       = aws_wafv2_web_acl.waf_acl.arn
  sensitive   = false
  description = "The ARN of the WAF Web ACL"
}