# # S3 Bucket for storing CSV files
# resource "aws_s3_bucket" "csv_data_bucket" {
#   bucket = "zee-question-answer-data-bucket"
#   acl    = "private"
# }

# # DynamoDB table for tracking CSV processing
# resource "aws_dynamodb_table" "csv_tracking" {
#   name           = "CSVProcessingTracking"
#   billing_mode   = "PAY_PER_REQUEST"
#   hash_key       = "filename"

#   attribute {
#     name = "filename"
#     type = "S"
#   }

#   attribute {
#     name = "status"
#     type = "S"
#   }

#   attribute {
#     name = "processedRecords"
#     type = "N"
#   }

#   attribute {
#     name = "totalRecords"
#     type = "N"
#   }
# }

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
#   role          = aws_iam_role.lambda_execution_role.arn
#   source_code_hash = filebase64sha256("path_to_your_zip_file.zip")

#   # Replace this with the actual ZIP file containing your Lambda function
#   filename = "./path_to_your_lambda_zip.zip"

#   environment {
#     variables = {
#       DYNAMODB_TABLE_NAME = aws_dynamodb_table.csv_tracking.name
#     }
#   }
# }