# terraform {
#   backend "s3" {
#     bucket  = "zee-terraform-state-bucket"
#     key     = "prod/terraform.tfstate"
#     region  = "us-west-1"
#     encrypt = true
#     dynamodb_table = "terraform-up-and-running-locks"
#   }
# }

provider "aws" {
  region = "us-west-1"
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-ssh-key-final"
  public_key = file("/tmp/chroma-aws.pub")
}

resource "aws_secretsmanager_secret" "example_secret" {
  name = "example_secret"
}

locals {
  combined_secret = {
    username          = "testuser",
    password          = "mypassword",
    PUBLIC_IP_ADDRESS = aws_instance.chroma_instance.public_ip,
    CHROMA_AUTH_TOKEN = random_password.chroma_token.result
  }
}

resource "aws_secretsmanager_secret_version" "example_secret_version" {
  secret_id     = aws_secretsmanager_secret.example_secret.id
  secret_string = jsonencode(local.combined_secret)
}


resource "aws_iam_policy" "access_secrets" {
  name        = "AccessSecrets"
  description = "Allow access to Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "secretsmanager:GetSecretValue",
        Resource = aws_secretsmanager_secret.example_secret.arn,
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_secrets_access" {
  policy_arn = aws_iam_policy.access_secrets.arn
  role       = aws_iam_role.ec2_role.name
}

resource "aws_instance" "docker_host" {
  ami             = "ami-073e64e4c237c08ad" # This is an Amazon Linux 2 LTS AMI. Make sure to use an updated one or the one relevant to your region.
  instance_type   = "t2.micro"

  key_name        = aws_key_pair.deployer.key_name # Ensure you have this key pair created or replace with your existing key pair name
  security_groups = [aws_security_group.allow_alb.name]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  user_data =  <<-EOT
              #!/bin/bash

              LOG_FILE="/home/ec2-user/user_data.log"

              echo "Starting user_data script..." >> $LOG_FILE

              echo "Updating system packages..." >> $LOG_FILE
              yum update -y >> $LOG_FILE 2>&1
              if [ $? -ne 0 ]; then echo "Error updating packages" >> $LOG_FILE; fi

              echo "Installing Docker..." >> $LOG_FILE
              yum install -y docker libxcrypt-compat >> $LOG_FILE 2>&1
              if [ $? -ne 0 ]; then echo "Error installing Docker" >> $LOG_FILE; fi

              echo "Starting Docker..." >> $LOG_FILE
              systemctl start docker
              systemctl enable docker

              usermod -a -G docker ec2-user
              echo "Installing Docker Compose..." >> $LOG_FILE
              curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose

              # Wait for a bit to ensure docker-compose is available for execution
              sleep 10

              echo "Creating Docker Compose file..."

              echo "Creating Docker Compose file..." >> $LOG_FILE
              cat <<-EOF > /home/ec2-user/docker-compose.yml
              version: '3'
              services:
                fastapi-app:
                  image: dekardar/terraform-aws:latest
                  build:
                    context: .
                    dockerfile: Dockerfile
                  ports:
                    - '80:80'
                  environment:
                    - AWS_DEFAULT_REGION=us-west-1
              EOF

              echo "Pulling Docker images..." >> $LOG_FILE
              /usr/local/bin/docker-compose -f /home/ec2-user/docker-compose.yml pull fastapi-app >> $LOG_FILE 2>&1
              if [ $? -ne 0 ]; then echo "Error pulling Docker images" >> $LOG_FILE; fi

              echo "Starting Docker containers..." >> $LOG_FILE
              /usr/local/bin/docker-compose -f /home/ec2-user/docker-compose.yml up -d >> $LOG_FILE 2>&1
              if [ $? -ne 0 ]; then echo "Error starting Docker containers" >> $LOG_FILE; fi

              echo "Finished user_data script." >> $LOG_FILE
EOT


  tags = {
    Name = "DockerHost"
  }
}



resource "aws_security_group" "allow_alb" {
  name        = "allow_inbound_outbound_traffic_final"
  description = "Allow all inbound and outbound traffic"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # This means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ...

# CloudWatch Log Group and Stream
resource "aws_cloudwatch_log_group" "app_log_group" {
  name = "custom-search-app-log-group"
}

resource "aws_cloudwatch_log_stream" "app_log_stream" {
  name           = "custom-search-app-log-stream"
  log_group_name = aws_cloudwatch_log_group.app_log_group.name
}

# IAM Policy for EC2 to write logs to CloudWatch
resource "aws_iam_policy" "ec2_cloudwatch_logs" {
  name        = "EC2CloudWatchLogs"
  description = "Allow EC2 to write to CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ],
        Resource = "${aws_cloudwatch_log_group.app_log_group.arn}:*",
        Effect   = "Allow"
      }
    ]
  })
}

# Attach the CloudWatch logs policy to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_logs_access" {
  policy_arn = aws_iam_policy.ec2_cloudwatch_logs.arn
  role       = aws_iam_role.ec2_role.name
}

# CloudWatch Metric Filter to monitor endpoint calls
resource "aws_cloudwatch_log_metric_filter" "search_endpoint_calls" {
  name           = "SearchEndpointCalls"
  pattern        = "Searching"  # Adjust the pattern to match your log format
  log_group_name = aws_cloudwatch_log_group.app_log_group.name

  metric_transformation {
    name      = "EndpointSearchCallCount"
    namespace = "App/Endpoints"
    value     = "1"
  }
}

# CloudWatch Metric Filter to monitor endpoint calls
resource "aws_cloudwatch_log_metric_filter" "index_endpoint_calls" {
  name           = "IndexEndpointCalls"
  pattern        = "Indexing"  # Adjust the pattern to match your log format
  log_group_name = aws_cloudwatch_log_group.app_log_group.name

  metric_transformation {
    name      = "EndpointIndexCallCount"
    namespace = "App/Endpoints"
    value     = "1"
  }
}

# CloudWatch Dashboard
# CloudWatch Dashboard
# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "app_dashboard" {
  dashboard_name = "App-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        x    = 0,
        y    = 0,
        width = 12,
        properties = {
          metrics = [
            ["App/Endpoints", "EndpointSearchCallCount", { "region": "us-west-1" }]
          ],
          period  = 300,
          stat    = "Sum",
          region  = "us-west-1",
          title   = "Endpoint Search Calls",
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type = "metric",
        x    = 0,
        y    = 6,
        width = 12,
        properties = {
          metrics = [
            ["App/Endpoints", "EndpointIndexCallCount", { "region": "us-west-1" }]
          ],
          period  = 300,
          stat    = "Sum",
          region  = "us-west-1",
          title   = "Endpoint Index Calls",
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type = "number",
        x    = 12,
        y    = 0,
        width = 6,
        properties = {
          metrics = [
            ["App/Endpoints", "EndpointSearchCallCount", { "region": "us-west-1" }]
          ],
          period  = 300,
          stat    = "Sum",
          region  = "us-west-1",
          title   = "Endpoint Search Calls (Text)"
        }
      },
      {
        type = "number",
        x    = 12,
        y    = 6,
        width = 6,
        properties = {
          metrics = [
            ["App/Endpoints", "EndpointIndexCallCount", { "region": "us-west-1" }]
          ],
          period  = 300,
          stat    = "Sum",
          region  = "us-west-1",
          title   = "Endpoint Index Calls (Text)"
        }
      }
    ]
  })
}