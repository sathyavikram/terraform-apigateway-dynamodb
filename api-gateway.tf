# Create openapi template for rest api
data "template_file" "openapi_template" {
  template = templatefile("${path.module}/openapi.json", {
    BooksTableName = "${aws_dynamodb_table.books-dynamodb-table.id}",
    CurrentRegion         = "${data.aws_region.current.name}"
    ModifyDataRoleArn     = "${aws_iam_role.apigateway_modify_data_in_db.arn}"
    ReadDataRoleArn    = "${aws_iam_role.apigateway_db_read_data_role.arn}"
  })
}

data "aws_region" "current" {}

data "aws_iam_policy_document" "apigateway_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigateway_modify_data_in_db" {
  name               = "apigateway_modify_data_in_db"
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume_role_policy.json

  inline_policy {
    name = "apigateway_modify_data_in_db_inline_policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem"]
          Effect   = "Allow"
          Resource = ["${aws_dynamodb_table.books-dynamodb-table.arn}"]
        },
      ]
    })
  }
}

resource "aws_iam_role" "apigateway_db_read_data_role" {
  name               = "apigateway_db_read_data_role"
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume_role_policy.json

  inline_policy {
    name = "apigateway_db_read_data_inline_policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["dynamodb:Query", "dynamodb:GetItem"]
          Effect   = "Allow"
          Resource = ["${aws_dynamodb_table.books-dynamodb-table.arn}"]
        },
      ]
    })
  }
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

