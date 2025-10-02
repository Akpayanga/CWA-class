output "dashboard_url" {
  value = "https://${aws_cloudfront_distribution.dashboard_distribution.domain_name}"
}

output "api_endpoint" {
  value = "https://${aws_api_gateway_rest_api.cost_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/cost"
}
