# Create openapi template for rest api
data "template_file" "openapi_template" {
  template = templatefile("${path.module}/openapi.json", {})
}

#Create a new API Gateway rest api with DynamoDB Integration
resource "aws_api_gateway_rest_api" "BooksApi" {
  name = "Books api"
  body = data.template_file.openapi_template.rendered
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Create a new API Gateway deployment for the created rest api
resource "aws_api_gateway_deployment" "BooksApi" {
  rest_api_id = aws_api_gateway_rest_api.BooksApi.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.BooksApi.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}


# Create a Log Group for API Gateway to push logs to
resource "aws_cloudwatch_log_group" "BooksApiLogGroup" {
  name_prefix = "/aws/APIGW/books"
}

# Create a Log Policy to allow Cloudwatch to Create log streams and put logs
resource "aws_cloudwatch_log_resource_policy" "BooksCloudWatchLogPolicy" {
  policy_name     = "BooksCloudWatchLogPolicy"
  policy_document = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "BooksCloudWatchLogPolicy",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [ 
          "apigateway.amazonaws.com",
          "delivery.logs.amazonaws.com"
          ]
      },
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
        ],
      "Resource": "${aws_cloudwatch_log_group.BooksApiLogGroup.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_api_gateway_rest_api.BooksApi.arn}"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_api_gateway_account" "ApiGatewayAccountSetting" {
  cloudwatch_role_arn = aws_iam_role.APIGatewayCloudWatchRole.arn
}

resource "aws_iam_role" "APIGatewayCloudWatchRole" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "APIGatewayCloudWatchPolicy" {
  role = aws_iam_role.APIGatewayCloudWatchRole.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "logs:GetLogEvents",
                "logs:FilterLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

# Configure API Gateway to push all logs to CloudWatch Logs
resource "aws_api_gateway_method_settings" "ApiGatewaySetting" {
  rest_api_id = aws_api_gateway_rest_api.BooksApi.id
  stage_name  = aws_api_gateway_stage.BooksApi.stage_name
  method_path = "*/*"

  settings {
    # Enable CloudWatch logging and metrics
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

# Create a new API Gateway stage with logging enabled
resource "aws_api_gateway_stage" "BooksApi" {
  deployment_id = aws_api_gateway_deployment.BooksApi.id
  rest_api_id   = aws_api_gateway_rest_api.BooksApi.id
  stage_name    = "dev"
  depends_on    = [aws_api_gateway_account.ApiGatewayAccountSetting]

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.BooksApiLogGroup.arn
    format          = "{ \"requestId\":\"$context.requestId\", \"ip\": \"$context.identity.sourceIp\", \"requestTime\":\"$context.requestTime\", \"httpMethod\":\"$context.httpMethod\",\"status\":\"$context.status\",\"protocol\":\"$context.protocol\", \"responseLength\":\"$context.responseLength\" }"
  }
}

