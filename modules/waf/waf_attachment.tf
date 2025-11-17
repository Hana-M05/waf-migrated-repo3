# Data block to look up ALBs by name
data "aws_lb" "target_albs" {
  for_each = toset(var.alb_names)
  name     = each.value
}

# Associate WAF with ALBs
resource "aws_wafv2_web_acl_association" "alb_association" {
  for_each = data.aws_lb.target_albs

  resource_arn = each.value.arn
  web_acl_arn  = aws_wafv2_web_acl.waf_acl.arn
}

# Data block to look up API Gateways by ID
data "aws_apigatewayv2_api" "target_apis" {
  for_each = toset(var.api_gateway_ids)
  api_id   = each.value
}

# Associate WAF with API Gateways
resource "aws_wafv2_web_acl_association" "api_gateway_v2_association" {
  for_each = data.aws_apigatewayv2_api.target_apis

  resource_arn = each.value.arn
  web_acl_arn  = aws_wafv2_web_acl.waf_acl.arn
}