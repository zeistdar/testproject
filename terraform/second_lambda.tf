resource "aws_s3_bucket" "csv_bucket" {
  bucket = "zee-csv-faqs-bucket-name" # Change this to your desired bucket name

}

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

resource "aws_lambda_function" "process_csv" {
  function_name = "ProcessCSVData"
  handler       = "index.handler"
  runtime       = "python3.11"

  # Assuming you have a deployment package named "lambda_function_payload.zip" in your working directory
  filename = "/tmp/lambda.zip"
  source_code_hash = filebase64sha256("/tmp/lambda.zip")
  timeout = 300
  memory_size   = 512
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.csv_tracking.name
      ALB_DNS_NAME        = aws_lb.this.dns_name
    }
  }
  
  role = aws_iam_role.lambda_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_new_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_access_event" {
  policy_arn = aws_iam_policy.lambda_s3_new_access.arn
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_iam_policy" "lambda_s3_new_access" {
  name        = "LambdaS3AccessPolicy"
  description = "Allows lambda function to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject"
        ],
        Resource = "${aws_s3_bucket.csv_bucket.arn}/*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*",
        Effect   = "Allow"
      },
      {
        Action = [
          "s3:ListBucket"
        ],
        Resource = aws_s3_bucket.csv_bucket.arn,
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "bucket_notification_lambda" {
  bucket = aws_s3_bucket.csv_bucket.bucket

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_csv.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

resource "aws_lambda_permission" "allow_bucket_access" {
  statement_id  = "AllowS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_csv.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.csv_bucket.arn
}

resource "aws_iam_policy" "dynamodb_access_policy_event" {
  name        = "DynamoDBAccessPolicyEvent"
  description = "Allow access to DynamoDB table"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:Scan",
          "dynamodb:DeleteItem"
        ],
        Resource = [
          aws_dynamodb_table.csv_tracking.arn,
          "${aws_dynamodb_table.csv_tracking.arn}/CSVProcessingTracking/*"
        ]
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access_event" {
  policy_arn = aws_iam_policy.dynamodb_access_policy_event.arn
  role       = aws_iam_role.lambda_exec.name
}