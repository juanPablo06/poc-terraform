terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_security_group" "default" {
  name = "default"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sqs:SendMessage"
    ]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda.js"
  output_path = "lambda_function_payload.zip"
}

resource "aws_sqs_queue" "test_lambda_dl_queue" {
  name = "test_lambda_dl_queue"
}

resource "aws_signer_signing_profile" "default" {
  name        = "test"
  platform_id = "AWSLambda-SHA384-ECDSA"
  signature_validity_period {
    value = 180
    type  = "DAYS"
  }
}

resource "aws_lambda_code_signing_config" "default" {
  description = "test"

  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.default.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
}

resource "aws_lambda_function" "test_lambda" {
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  filename      = "lambda_function_payload.zip"
  function_name = "lambda_function_name"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "index.test"

  source_code_hash = data.archive_file.lambda.output_base64sha256

  runtime = "nodejs18.x"

  reserved_concurrent_executions = 1

  dead_letter_config {
    target_arn = aws_sqs_queue.test_lambda_dl_queue.arn
  }

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [data.aws_security_group.default.id]
  }

  code_signing_config_arn = aws_lambda_code_signing_config.default.arn
}
