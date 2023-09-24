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

