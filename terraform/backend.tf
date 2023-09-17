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
  current_time = replace(timestamp(), ":", "-")
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

# resource "aws_instance" "docker_host" {
#   ami             = "ami-073e64e4c237c08ad" # This is an Amazon Linux 2 LTS AMI. Make sure to use an updated one or the one relevant to your region.
#   instance_type   = "t2.micro"

#   key_name        = aws_key_pair.deployer.key_name # Ensure you have this key pair created or replace with your existing key pair name
#   security_groups = [aws_security_group.allow_alb.name]
#   iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
#   user_data =  <<-EOT
#               #!/bin/bash

#               LOG_FILE="/home/ec2-user/user_data.log"

#               echo "Starting user_data script..." >> $LOG_FILE

#               echo "Updating system packages..." >> $LOG_FILE
#               yum update -y >> $LOG_FILE 2>&1
#               if [ $? -ne 0 ]; then echo "Error updating packages" >> $LOG_FILE; fi

#               echo "Installing Docker..." >> $LOG_FILE
#               yum install -y docker libxcrypt-compat >> $LOG_FILE 2>&1
#               if [ $? -ne 0 ]; then echo "Error installing Docker" >> $LOG_FILE; fi

#               echo "Starting Docker..." >> $LOG_FILE
#               systemctl start docker
#               systemctl enable docker

#               usermod -a -G docker ec2-user
#               echo "Installing Docker Compose..." >> $LOG_FILE
#               curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
#               chmod +x /usr/local/bin/docker-compose

#               # Wait for a bit to ensure docker-compose is available for execution
#               sleep 10

#               echo "Creating Docker Compose file..."

#               echo "Creating Docker Compose file..." >> $LOG_FILE
#               cat <<-EOF > /home/ec2-user/docker-compose.yml
#               version: '3'
#               services:
#                 fastapi-app:
#                   image: dekardar/terraform-aws:latest
#                   build:
#                     context: .
#                     dockerfile: Dockerfile
#                   ports:
#                     - '80:80'
#                   environment:
#                     - AWS_DEFAULT_REGION=us-west-1
#               EOF

#               echo "Pulling Docker images..." >> $LOG_FILE
#               /usr/local/bin/docker-compose -f /home/ec2-user/docker-compose.yml pull fastapi-app >> $LOG_FILE 2>&1
#               if [ $? -ne 0 ]; then echo "Error pulling Docker images" >> $LOG_FILE; fi

#               echo "Starting Docker containers..." >> $LOG_FILE
#               /usr/local/bin/docker-compose -f /home/ec2-user/docker-compose.yml up -d >> $LOG_FILE 2>&1
#               if [ $? -ne 0 ]; then echo "Error starting Docker containers" >> $LOG_FILE; fi

#               echo "Finished user_data script." >> $LOG_FILE
# EOT


#   tags = {
#     Name = "DockerHost"
#   }
# }



resource "aws_security_group" "allow_alb" {
  name        = "allow_inbound_outbound_traffic_final"
  description = "Allow all inbound and outbound traffic"
  vpc_id = aws_vpc.custom_vpc.id

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

# CloudWatch Metric Filter to monitor endpoint calls
resource "aws_cloudwatch_log_metric_filter" "index_endpoint_errors" {
  name           = "IndexEndpointErrors"
  pattern        = "Index Failed"  # Adjust the pattern to match your log format
  log_group_name = aws_cloudwatch_log_group.app_log_group.name

  metric_transformation {
    name      = "EndpointIndexErrorCount"
    namespace = "App/Endpoints"
    value     = "1"
  }
}

# CloudWatch Metric Filter to monitor endpoint calls
resource "aws_cloudwatch_log_metric_filter" "search_endpoint_errors" {
  name           = "SearchEndpointErrors"
  pattern        = "Search Failed"  # Adjust the pattern to match your log format
  log_group_name = aws_cloudwatch_log_group.app_log_group.name

  metric_transformation {
    name      = "EndpointSearchErrorCount"
    namespace = "App/Endpoints"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "index_endpoint_error_alarm" {
  alarm_name          = "IndexEndpointErrorAlarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "EndpointIndexErrorCount"
  namespace           = "App/Endpoints"
  period              = "300"
  statistic           = "SampleCount"
  threshold           = "1"
  alarm_description   = "This metric triggers an alarm if the Index endpoint has errors"
  alarm_actions       = [] 
}

resource "aws_cloudwatch_metric_alarm" "search_endpoint_error_alarm" {
  alarm_name          = "SearchEndpointErrorAlarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "EndpointSearchErrorCount"
  namespace           = "App/Endpoints"
  period              = "300"
  statistic           = "SampleCount"
  threshold           = "1"
  alarm_description   = "This metric triggers an alarm if the Search endpoint has errors"
  alarm_actions       = []  
}



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
    type = "metric",
    x    = 12,
    y    = 0,
    width = 6,
    properties = {
      metrics = [
        ["App/Endpoints", "EndpointSearchCallCount", { "region": "us-west-1", "period": 300, "stat": "Sum" }]
      ],
      view   = "singleValue",
      region = "us-west-1",
      title  = "Endpoint Search Calls (Text)"
    }
  },
  {
    type = "metric",
    x    = 12,
    y    = 6,
    width = 6,
    properties = {
      metrics = [
        ["App/Endpoints", "EndpointIndexCallCount", { "region": "us-west-1", "period": 300, "stat": "Sum" }]
      ],
      view   = "singleValue",
      region = "us-west-1",
      title  = "Endpoint Index Calls (Text)"
    }
  },
  {
    type = "metric",
    x    = 0,
    y    = 12,
    width = 12,
    properties = {
      metrics = [
        ["App/Endpoints", "EndpointIndexErrorCount", { "region": "us-west-1", "period": 300, "stat": "Sum" }]
      ],
      view   = "singleValue",
      region = "us-west-1",
      title  = "Endpoint Index Error Calls (Text)"
    }
  },
  {
    type = "metric",
    x    = 12,
    y    = 12,
    width = 12,
    properties = {
      metrics = [
        ["App/Endpoints", "EndpointSearchErrorCount", { "region": "us-west-1", "period": 300, "stat": "Sum" }]
      ],
      view   = "singleValue",
      region = "us-west-1",
      title  = "Endpoint Search Error Calls (Text)"
    }
  }
  ]

  })
}

######################
resource "aws_vpc" "custom_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "CustomVPC"
  }
}

resource "aws_subnet" "custom_subnet" {
  vpc_id     = aws_vpc.custom_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-west-1a" 
  map_public_ip_on_launch = true

  tags = {
    Name = "CustomSubnet"
  }
}

resource "aws_subnet" "custom_subnet_2" {
  vpc_id     = aws_vpc.custom_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-west-1c" # Choose a different AZ than your first subnet
  map_public_ip_on_launch = true

  tags = {
    Name = "CustomSubnet2"
  }
}


resource "aws_internet_gateway" "custom_igw" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "CustomIGW"
  }
}

resource "aws_route_table" "custom_rt" {
  vpc_id = aws_vpc.custom_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.custom_igw.id
  }

  tags = {
    Name = "CustomRT"
  }
}

resource "aws_route_table_association" "custom_rta" {
  subnet_id      = aws_subnet.custom_subnet.id
  route_table_id = aws_route_table.custom_rt.id
}

resource "aws_route_table_association" "custom_rta_2" {
  subnet_id      = aws_subnet.custom_subnet_2.id
  route_table_id = aws_route_table.custom_rt.id
}





######################
resource "aws_lb_target_group" "tg" {
  name     = "fastapi-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.custom_vpc.id

  health_check {
    enabled             = true
    interval            = 30
    path                = "/" 
    port                = "80"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb" "this" {
  name               = "fastapi-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_alb.id]
  subnets            = [aws_subnet.custom_subnet.id, aws_subnet.custom_subnet_2.id]

  enable_deletion_protection = false

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}


resource "aws_launch_configuration" "as_conf" {
  name_prefix   = "fastapi-${local.current_time}-"
  image_id      = "ami-073e64e4c237c08ad" # This is an Amazon Linux 2 LTS AMI. Make sure to use an updated one or the one relevant to your region.
  instance_type   = "t2.micro"

  key_name        = aws_key_pair.deployer.key_name # Ensure you have this key pair created or replace with your existing key pair name
  security_groups = [aws_security_group.allow_alb.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  depends_on = [aws_security_group.allow_alb]
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

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_autoscaling_group" "as_group" {
  name                 = "fastapi-${aws_launch_configuration.as_conf.name_prefix}"
  launch_configuration = aws_launch_configuration.as_conf.name
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1

  vpc_zone_identifier = [aws_subnet.custom_subnet.id, aws_subnet.custom_subnet_2.id]

  target_group_arns = [aws_lb_target_group.tg.arn]

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_cloudwatch_metric_alarm" "scale_up" {
  alarm_name          = "cpu-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "70" # Scale up if CPU > 70%

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.as_group.name
  }

  alarm_description = "This metric triggers an increase in the instance count of the ASG"
  alarm_actions     = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "scale_down" {
  alarm_name          = "cpu-utilization-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "20" # Scale down if CPU < 20%

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.as_group.name
  }

  alarm_description = "This metric triggers a decrease in the instance count of the ASG"
  alarm_actions     = [aws_autoscaling_policy.scale_down.arn]
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.as_group.name
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.as_group.name
  cooldown               = 300
}

resource "aws_dynamodb_table" "qa_table" {
  name           = "QATable"
  billing_mode   = "PROVISIONED"
  hash_key       = "id"  # Using id as the primary key
  range_key      = "date"  # Using date as the range key
  read_capacity  = 10
  write_capacity = 10

  attribute {
    name = "question"
    type = "S"
  }

  attribute {
    name = "answer"
    type = "S"
  }

  attribute {
    name = "form_type"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "date"
    type = "S"
  }

  global_secondary_index {
    name               = "FormTypeIndex"
    hash_key           = "form_type"
    write_capacity     = 10
    read_capacity      = 10
    projection_type    = "ALL"
  }

  global_secondary_index {
    name               = "QuestionAnswerIndex"
    hash_key           = "question"
    range_key          = "answer"
    write_capacity     = 10
    read_capacity      = 10
    projection_type    = "ALL"
  }
}

resource "aws_iam_policy" "dynamodb_access_policy" {
  name        = "DynamoDBAccessPolicy"
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
        Resource = aws_dynamodb_table.qa_table.arn,
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_dynamodb_access" {
  policy_arn = aws_iam_policy.dynamodb_access_policy.arn
  role       = aws_iam_role.ec2_role.name
}

