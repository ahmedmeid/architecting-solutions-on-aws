terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Task 1. Setup: Creating IAM policies and roles

# Step 1.1: Creating custom IAM policies

resource "aws_iam_policy" "lambda-write-dynamodb" {
  name        = "Lambda-Write-DynamoDB"
  path        = "/"
  description = "Policy for Lambda function to write on DynamoDB"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:DescribeTable"
            ],
            "Resource": "*"
        }
    ]
})
}

resource "aws_iam_policy" "lambda-sns-publish" {
  name        = "Lambda-SNS-Publish"
  path        = "/"
  description = "Policy for Lambda function to publish on SNS"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "sns:Publish",
                "sns:GetTopicAttributes",
                    "sns:ListTopics"
            ],
                "Resource": "*"
        }
    ]
 })
}

resource "aws_iam_policy" "lambda-dynamodbstreams-read" {
  name        = "Lambda-DynamoDBStreams-Read"
  path        = "/"
  description = "Policy for Lambda function to read from dynamodb streams"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetShardIterator",
                "dynamodb:DescribeStream",
                "dynamodb:ListStreams",
                "dynamodb:GetRecords"
            ],
            "Resource": "*"
        }
    ]
})
}

resource "aws_iam_policy" "lambda-read-sqs" {
  name        = "Lambda-Read-SQS"
  path        = "/"
  description = "Policy for Lambda function to read from SQS"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "sqs:DeleteMessage",
                "sqs:ReceiveMessage",
                "sqs:GetQueueAttributes",
                "sqs:ChangeMessageVisibility"
            ],
            "Resource": "*"
        }
    ]
})
}

# Step 1.2: Creating IAM roles and attaching policies to the roles

data "aws_iam_policy_document" "assume_lambda_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda-sqs-dynamodb" {
  name = "Lambda-SQS-DynamoDB"

  assume_role_policy = data.aws_iam_policy_document.assume_lambda_role.json
}

resource "aws_iam_role_policy_attachment" "attach-lambda-write-dynamodb" {
  role       = aws_iam_role.lambda-sqs-dynamodb.name
  policy_arn = aws_iam_policy.lambda-write-dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "attach-lambda-read-sqs" {
  role       = aws_iam_role.lambda-sqs-dynamodb.name
  policy_arn = aws_iam_policy.lambda-read-sqs.arn
}

resource "aws_iam_role" "lambda-dynamodbstreams-sns" {
  name = "Lambda-DynamoDBStreams-SNS"

  assume_role_policy = data.aws_iam_policy_document.assume_lambda_role.json
}

resource "aws_iam_role_policy_attachment" "attach-lambda-sns-publish" {
  role       = aws_iam_role.lambda-dynamodbstreams-sns.name
  policy_arn = aws_iam_policy.lambda-sns-publish.arn
}

resource "aws_iam_role_policy_attachment" "attach-lambda-dynamodbstreams-read" {
  role       = aws_iam_role.lambda-dynamodbstreams-sns.name
  policy_arn = aws_iam_policy.lambda-dynamodbstreams-read.arn
}

resource "aws_iam_role" "apigateway-sqs" {
  name = "APIGateway-SQS"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach-apigateway-cloudwatchlogs" {
  role       = aws_iam_role.apigateway-sqs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# Task 2: Creating a DynamoDB table
resource "aws_dynamodb_table" "orders" {
  name             = "orders"
  hash_key         = "orderID"
  billing_mode     = "PAY_PER_REQUEST"
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  attribute {
    name = "orderID"
    type = "S"
  }
}

# Task 3: Creating an SQS queue

resource "aws_sqs_queue" "poc_queue" {
  name                      = "POC-Queue"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 345600 # 4 days
  visibility_timeout_seconds = 30

  policy = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "AWS": aws_iam_role.apigateway-sqs.arn
          },
          "Action": "sqs:SendMessage",
          "Resource": "*"
        },
        {
          "Effect": "Allow",
          "Principal": {
            "AWS": aws_iam_role.lambda-sqs-dynamodb.arn
          },
          "Action": "sqs:ReceiveMessage",
          "Resource": "*"
        }
      ]
    })
}

# Task 4: Creating a Lambda function and setting up triggers
# Step 4.1: Creating a Lambda function for the Lambda-SQS-DynamoDB role

data "archive_file" "poc_lambda_1_package" {  
  type = "zip"  
  source_file = "${path.module}/poc_lambda_1/lambda_function.py" 
  output_path = "poc_lambda_1.zip"
}

resource "aws_lambda_function" "poc_lambda1" {
  filename      = "poc_lambda_1.zip"
  function_name = "POC-Lambda-1"
  role          = aws_iam_role.lambda-sqs-dynamodb.arn
  handler       = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.poc_lambda_1_package.output_base64sha256
  runtime = "python3.9"
  timeout       = 30
}

# Step 4.2: Setting up Amazon SQS as a trigger to invoke the function
resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  event_source_arn = aws_sqs_queue.poc_queue.arn
  function_name    = aws_lambda_function.poc_lambda1.arn
}

# Task 5: Enabling DynamoDB Streams
# this task has been already done in task 2 during creation of dynamodb table 

# Task 6: Creating an SNS topic and setting up subscriptions

# Step 6.1: Creating a topic in the notification service
resource "aws_sns_topic" "poc_topic" {
  name = "POC-Topic"
}

# Step 6.2: Subscribing to email notifications
resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = aws_sns_topic.poc_topic.arn
  protocol  = "email"
  endpoint  = "ahmed.eid@gmx.com"
}

# Task 7: Creating an AWS Lambda function to publish a message to the SNS topic
# Step 7.1: Creating a POC-Lambda-2 function
data "archive_file" "poc_lambda_2_package" {  
  type = "zip"  
  source_file = "${path.module}/poc_lambda_2/lambda_function.py" 
  output_path = "poc_lambda_2.zip"
}

resource "aws_lambda_function" "poc_lambda2" {
  filename      = "poc_lambda_2.zip"
  function_name = "POC-Lambda-2"
  role          = aws_iam_role.lambda-sqs-dynamodb.arn
  handler       = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.poc_lambda_2_package.output_base64sha256
  runtime = "python3.9"
  timeout       = 30
}

# Step 7.2: Setting up DynamoDB as a trigger to invoke a Lambda function
resource "aws_lambda_event_source_mapping" "example_mapping" {
  event_source_arn = aws_dynamodb_table.orders.stream_arn
  function_name    = aws_lambda_function.poc_lambda2.arn
  starting_position = "LATEST" # Change if needed
}

# Task 8: Creating an API with Amazon API Gateway
resource "aws_api_gateway_rest_api" "poc_api" {
  name          = "POC-API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.poc_api.id
  parent_id   = aws_api_gateway_rest_api.poc_api.root_resource_id
  path_part   = "/" 

}

# Create the POST method
resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.poc_api.id
  resource_id   = aws_api_gateway_resource.root.id
  http_method   = "POST"
  authorization = "NONE"
}

# Configure integration
resource "aws_api_gateway_integration" "sqs_integration" {
  rest_api_id = aws_api_gateway_rest_api.poc_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.post_method.http_method
  type        = "AWS"
  integration_http_method = "POST"
  uri         = aws_sqs_queue.poc_queue.arn
  credentials = "arn:aws:iam::950816420455:role/APIGateway-SQS" 
  passthrough_behavior = "NEVER"
  
  request_parameters = {
    "integration.request.path.override" = "/950816420455/POC-Queue" 
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$input.body"
  }
}
