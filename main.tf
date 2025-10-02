provider "aws" {
  region = var.aws_region
}

# VPC Setup (Basic)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "cost-tracker-vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name = "cost-tracker-subnet"
  }
}

# DynamoDB Table (for cost and usage logs)
resource "aws_dynamodb_table" "cost_logs" {
  name           = "CostLogs"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "Timestamp"

  attribute {
    name = "Timestamp"
    type = "S"
  }

  tags = {
    Name = "CostLogsTable"
  }
}

# CloudWatch Metrics and Alarms (to monitor estimated billing)
resource "aws_cloudwatch_metric_alarm" "billing_alarm" {
  alarm_name          = "EstimatedBillingAlarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400" # 1 day
  statistic           = "Maximum"
  threshold           = var.cost_threshold
  alarm_description   = "This alarm triggers when estimated charges exceed ${var.cost_threshold} USD"

  alarm_actions = [aws_sns_topic.cost_alerts.arn]
}

# SNS Topic & Subscription (for notifications when thresholds are crossed)
resource "aws_sns_topic" "cost_alerts" {
  name = "CostAlertsTopic"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# Lambda Function (triggered by EventBridge to log cost data)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "cost_tracker" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "CostTracker"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "cost_tracker.lambda_handler"
  runtime       = "python3.9"

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.cost_logs.name
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "cost_explorer_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess"
}

resource "aws_iam_role_policy" "dynamodb_access" {
  name   = "dynamodb_access_policy"
  role   = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:DescribeTable",
        "dynamodb:Scan",  # Enables reading logs for dashboard
        "dynamodb:GetItem"
      ]
      Resource = aws_dynamodb_table.cost_logs.arn
    }]
  })
}

# EventBridge (to schedule Lambda execution)
resource "aws_cloudwatch_event_rule" "cost_logging_schedule" {
  name                = "CostLoggingSchedule"
  schedule_expression = "rate(1 day)" # Runs once a day
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.cost_logging_schedule.name
  target_id = "CostTracker"
  arn       = aws_lambda_function.cost_tracker.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_tracker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_logging_schedule.arn
}

# API Gateway (Optional Extension - exposes cost data as an API)
resource "aws_api_gateway_rest_api" "cost_api" {
  name        = "CostAPI"
  description = "API for cost data"
}

resource "aws_api_gateway_resource" "cost_resource" {
  rest_api_id = aws_api_gateway_rest_api.cost_api.id
  parent_id   = aws_api_gateway_rest_api.cost_api.root_resource_id
  path_part   = "cost"
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.cost_api.id
  resource_id   = aws_api_gateway_resource.cost_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.cost_api.id
  resource_id             = aws_api_gateway_resource.cost_resource.id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.cost_tracker.invoke_arn
}

# CORS Method (OPTIONS for preflight requests)
resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.cost_api.id
  resource_id   = aws_api_gateway_resource.cost_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.cost_api.id
  resource_id = aws_api_gateway_resource.cost_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.cost_api.id
  resource_id = aws_api_gateway_resource.cost_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.cost_api.id
  resource_id = aws_api_gateway_resource.cost_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Deployment (single block with CORS depends_on)
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.options_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.cost_api.id
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_tracker.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.cost_api.execution_arn}/*/*"
}

resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.cost_api.id
  stage_name    = "prod"

  xray_tracing_enabled = false  # Optional: Enable if you want tracing
}

# S3 and CloudFront (Static Dashboard - frontend HTML page fetching data via API)

# Random ID for unique bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# S3 Bucket (Private - no public access)
resource "aws_s3_bucket" "dashboard_bucket" {
  bucket = "cost-tracker-dashboard-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "CostTrackerDashboard"
  }
}

# S3 Bucket Ownership Controls (required for modern ACL handling)
resource "aws_s3_bucket_ownership_controls" "dashboard_bucket_ownership" {
  bucket = aws_s3_bucket.dashboard_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# S3 Bucket Public Access Block (Fully enabled for security - blocks all public access)
resource "aws_s3_bucket_public_access_block" "dashboard_bucket_public_access" {
  bucket = aws_s3_bucket.dashboard_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Policy (Allows ONLY CloudFront OAC to read objects - private access)
resource "aws_s3_bucket_policy" "dashboard_bucket_policy" {
  bucket = aws_s3_bucket.dashboard_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.dashboard_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.dashboard_distribution.arn
          }
        }
      }
    ]
  })
}

# S3 Object (Private upload - no ACL; CloudFront handles access via OAC)
resource "aws_s3_object" "index_html" {
  bucket = aws_s3_bucket.dashboard_bucket.bucket
  key    = "index.html"
  source = "${path.module}/frontend/index.html"

  content_type = "text/html"

  # No ACL needed - bucket policy + OAC handles read access
}

# CloudFront Origin Access Control (OAC - allows private S3 access)
resource "aws_cloudfront_origin_access_control" "dashboard_oac" {
  name                              = "dashboard-oac"
  description                       = "OAC for Cost Tracker Dashboard"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution (Updated with OAC for private S3 origin)
resource "aws_cloudfront_distribution" "dashboard_distribution" {
  origin {
    domain_name              = aws_s3_bucket.dashboard_bucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.dashboard_bucket.bucket}"
    origin_access_control_id = aws_cloudfront_origin_access_control.dashboard_oac.id
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.dashboard_bucket.bucket}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
