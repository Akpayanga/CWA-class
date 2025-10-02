variable "aws_region" {
  default = "us-east-1"
}

variable "sns_email" {
  description = "Email address for SNS subscription"
  default     = "akpayangadaniel@gmail.com"
}

variable "cost_threshold" {
  description = "Cost threshold for CloudWatch alarm (in USD)"
  default     = 0.01
}
