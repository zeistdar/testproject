# # S3 Bucket for storing CSV files
# resource "aws_s3_bucket" "csv_data_bucket" {
#   bucket = "zee-csv-data-bucket"
# }

# DynamoDB table for tracking CSV processing
resource "aws_dynamodb_table" "csv_tracking" {
  name           = "CSVProcessingTracking"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "filename"

  attribute {
    name = "filename"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "processedRecords"
    type = "N"
  }

  attribute {
    name = "totalRecords"
    type = "N"
  }

  global_secondary_index {
    name               = "StatusIndex"
    hash_key           = "status"
    write_capacity     = 10
    read_capacity      = 10
    projection_type    = "ALL"
  }

  global_secondary_index {
    name               = "RecordsIndex"
    hash_key           = "processedRecords"
    range_key          = "totalRecords"
    write_capacity     = 10
    read_capacity      = 10
    projection_type    = "ALL"
  }
}

# # IAM Role and Permissions for Lambda
# resource "aws_iam_role" "lambda_execution_role" {
#   name = "LambdaExecutionRole"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action = "sts:AssumeRole",
#         Principal = {
#           Service = "lambda.amazonaws.com"
#         },
#         Effect = "Allow",
#         Sid    = ""
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
#   role       = aws_iam_role.lambda_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
# }

# resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
#   role       = aws_iam_role.lambda_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
# }

# resource "aws_lambda_function" "csv_processor" {
#   function_name = "CSVProcessor"
#   handler       = "index.handler"
#   runtime       = "python3.8"
#   source_code_hash = filebase64sha256("../lambda.zip")
#   role          = aws_iam_role.lambda_execution_role.arn
#   timeout = 300
#   memory_size   = 512

#   # Replace this with the actual ZIP file containing your Lambda function
#   filename = "../lambda.zip"

#   environment {
#     variables = {
#       DYNAMODB_TABLE_NAME = aws_dynamodb_table.csv_tracking.name
#       ALB_DNS_NAME        = aws_lb.this.dns_name
#     }
#   }

# #   vpc_config {
# #     subnet_ids         = [aws_subnet.custom_subnet.id, aws_subnet.custom_subnet_2.id]
# #     security_group_ids = [aws_security_group.lambda_sg.id]
# #     }

# }

# resource "aws_s3_bucket_notification" "bucket_notification" {
#   bucket = aws_s3_bucket.csv_test_data_bucket.id

#   lambda_function {
#     lambda_function_arn = aws_lambda_function.csv_processor.arn
#     events              = ["s3:ObjectCreated:*"]
#     filter_prefix       = ""  # You can specify a prefix if needed, e.g., "data/"
#     filter_suffix       = ".csv"
#   }
# }

# resource "aws_lambda_permission" "allow_bucket" {
#   statement_id  = "AllowExecutionFromS3Bucket"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.csv_processor.function_name
#   principal     = "s3.amazonaws.com"
#   source_arn    = "${aws_s3_bucket.csv_data_bucket.arn}"
# }




resource "aws_security_group" "lambda_sg" {
  name        = "lambda-sg"
  description = "Security group for Lambda function"
  vpc_id      = aws_vpc.custom_vpc.id
}

# # resource "aws_security_group_rule" "lambda_to_alb" {
# #   type        = "egress"
# #   from_port   = 80
# #   to_port     = 80
# #   protocol    = "tcp"
# #   cidr_blocks = flatten([for rule in aws_security_group.allow_alb.egress : rule.cidr_blocks])
# #   security_group_id = aws_security_group.lambda_sg.id
# # }

# # resource "aws_security_group_rule" "alb_from_lambda" {
# #   type        = "ingress"
# #   from_port   = 80
# #   to_port     = 80
# #   protocol    = "tcp"
# #   source_security_group_id = aws_security_group.lambda_sg.id
# #   security_group_id = aws_security_group.allow_alb.id
# # }

# # resource "aws_iam_policy" "lambda_vpc_access" {
# #   name        = "LambdaVPCAccess"
# #   description = "Allow Lambda functions to manage ENIs for VPC access"

# #   policy = jsonencode({
# #     Version = "2012-10-17",
# #     Statement = [
# #       {
# #         Action = [
# #           "ec2:CreateNetworkInterface",
# #           "ec2:DescribeNetworkInterfaces",
# #           "ec2:DeleteNetworkInterface"
# #         ],
# #         Resource = "*",
# #         Effect   = "Allow"
# #       }
# #     ]
# #   })
# # }

# # resource "aws_iam_role_policy_attachment" "lambda_vpc_access_attachment" {
# #   role       = aws_iam_role.lambda_execution_role.name
# #   policy_arn = aws_iam_policy.lambda_vpc_access.arn
# # }

# resource "aws_iam_policy" "lambda_secrets_access" {
#   name        = "LambdaSecretsAccess"
#   description = "Allow Lambda function to retrieve secrets from Secrets Manager"

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action   = "secretsmanager:GetSecretValue",
#         Resource = aws_secretsmanager_secret.example_secret.arn,
#         Effect   = "Allow"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "lambda_secrets_attachment" {
#   role       = aws_iam_role.lambda_execution_role.name
#   policy_arn = aws_iam_policy.lambda_secrets_access.arn
# }

# resource "aws_s3_bucket" "csv_test_data_bucket" {
#   bucket = "zee-test-csv-data-bucket"
# }

# resource "aws_iam_policy" "lambda_logging" {
#   name        = "LambdaLogging"
#   description = "Allow Lambda to write logs to CloudWatch"

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ],
#         Resource = "arn:aws:logs:*:*:*",
#         Effect   = "Allow"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "lambda_logging_attachment" {
#   role       = aws_iam_role.lambda_execution_role.name
#   policy_arn = aws_iam_policy.lambda_logging.arn
# }






# # IAM Role for Lambda
# # resource "aws_iam_role" "lambda_s3_execution_role" {
# #   name = "LambdaS3ExecutionRole"

# #   assume_role_policy = jsonencode({
# #     Version = "2012-10-17",
# #     Statement = [
# #       {
# #         Action = "sts:AssumeRole",
# #         Principal = {
# #           Service = "lambda.amazonaws.com"
# #         },
# #         Effect = "Allow",
# #         Sid    = ""
# #       }
# #     ]
# #   })
# # }

# # IAM Policy to give Lambda permissions for S3 and making API calls
# resource "aws_iam_role_policy" "lambda_s3_access" {
#   name = "LambdaS3Access"
#   role = aws_iam_role.lambda_execution_role.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action = [
#           "s3:GetObject",
#           "s3:ListBucket"
#         ],
#         Resource = [
#           aws_s3_bucket.csv_data_bucket.arn,
#           "${aws_s3_bucket.csv_data_bucket.arn}/*"
#         ],
#         Effect = "Allow"
#       },
#       {
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ],
#         Resource = "arn:aws:logs:*:*:*",
#         Effect   = "Allow"
#       },
#       {
#         Action = "execute-api:Invoke",
#         Resource = "*",
#         Effect   = "Allow"
#       }
#     ]
#   })
# }


