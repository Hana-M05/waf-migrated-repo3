locals {
  # Creates a mapping of ALB names to ARNs for easy lookup
  alb_arn_map = {
    for arn in var.alb_arns :
    # Extract the ALB name from the ARN
    split("/", arn)[length(split("/", arn)) - 2] => arn
  }
}

# Associate WAF with ALBs
resource "aws_wafv2_web_acl_association" "alb_association" {
  for_each = local.alb_arn_map

  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.waf_acl.arn
}

# Data block to look up API Gateways by ID
data "aws_apigatewayv2_api" "target_apis" {
  for_each = toset(var.api_gateway_ids)
  api_id   = each.value
}

# Associate WAF with API Gateways
resource "aws_wafv2_web_acl_association" "api_gateway_v2_association" {
  for_each = toset(var.api_gateway_ids)

  resource_arn = data.aws_apigatewayv2_api.target_apis[each.value].arn
  web_acl_arn  = aws_wafv2_web_acl.waf_acl.arn
}