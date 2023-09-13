# terraform {
#   backend "s3" {
#     bucket  = "zee-terraform-state-bucket"
#     key     = "prod/terraform.tfstate"
#     region  = "us-west-1"
#     encrypt = true
#     dynamodb_table = "terraform-up-and-running-locks"
#   }
# }

# provider "aws" {
#   region = "us-west-2"  # or your preferred region
# }

# # VPC and Subnets
# resource "aws_vpc" "my_vpc" {
#   cidr_block = "10.0.0.0/16"
# }

# resource "aws_subnet" "my_subnet" {
#   vpc_id     = aws_vpc.my_vpc.id
#   cidr_block = "10.0.1.0/24"
# }

# # Security Group
# resource "aws_security_group" "allow_alb" {
#   vpc_id = aws_vpc.my_vpc.id

#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   ingress {
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }


# # Load Balancer and Listener
# resource "aws_lb" "my_alb" {
#   name               = "my-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.allow_alb.id]
#   subnets            = [aws_subnet.my_subnet.id]
# }

# resource "aws_lb_listener" "front_end_https" {
#   load_balancer_arn = aws_lb.my_alb.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-2016-08"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.front_end.arn
#   }
# }

# resource "aws_lb_target_group" "front_end" {
#   name     = "front-end-tg"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = aws_vpc.my_vpc.id
# }

# # EC2 Autoscaling Group
# resource "aws_launch_configuration" "my_lc" {
#   # ... (similar to previous configuration)

#   security_groups = [aws_security_group.allow_alb.name]
#   associate_public_ip_address = true
#   instance_type = "t2.micro"
#   image_id      = "ami-0c55b159cbfafe1f0"  # Update this to your AMI
#   key_name      = aws_key_pair.my_key.key_name
#   user_data     = <<-EOF
#               #!/bin/bash
#               sudo apt-get update
#               sudo apt-get install -y docker.io
#               sudo curl -L "https://github.com/docker/compose/releases/download/1.28.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
#               sudo chmod +x /usr/local/bin/docker-compose
#               git clone https://github.com/your-username/your-repo.git /path/to/your/app
#               cd /path/to/your/app
#               sudo docker-compose up -d
#               EOF
# }

# resource "aws_autoscaling_group" "my_asg" {
#   launch_configuration = aws_launch_configuration.my_lc.name
#   min_size             = 1
#   max_size             = 3
#   desired_capacity     = 2
#   vpc_zone_identifier  = [aws_subnet.my_subnet.id]

#   tags = [
#     {
#       key                 = "Name"
#       value               = "my-asg-instance"
#       propagate_at_launch = true
#     }
#   ]
# }

# # CloudWatch Log Group
# resource "aws_cloudwatch_log_group" "app_logs" {
#   name = "my-app-logs"
#   retention_in_days = 14  # adjust as needed
# }

# # CloudWatch Dashboard
# resource "aws_cloudwatch_dashboard" "app_dashboard" {
#   dashboard_name = "MyApp-Dashboard"

#   dashboard_body = <<-EOF
#     {
#       "widgets": [
#         {
#           "type": "metric",
#           "x": 0,
#           "y": 0,
#           "width": 12,
#           "height": 6,
#           "properties": {
#             "metrics": [
#               [ "AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "${aws_autoscaling_group.my_asg.name}" ]
#             ],
#             "period": 300,
#             "title": "CPU Utilization"
#           }
#         }
#       ]
#     }
#   EOF
# }

# resource "aws_cloudwatch_metric_alarm" "high_cpu" {
#   alarm_name          = "high-cpu-alarm"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = "2"
#   metric_name         = "CPUUtilization"
#   namespace           = "AWS/EC2"
#   period              = "120"
#   statistic           = "Average"
#   threshold           = "80"
#   alarm_description   = "This metric checks if the CPU utilization exceeds 80% for two consecutive periods of 120 seconds"
#   alarm_actions       = [aws_sns_topic.cpu_alerts.arn]
#   dimensions = {
#     AutoScalingGroupName = aws_autoscaling_group.my_asg.name
#   }
# }

# resource "aws_sns_topic" "cpu_alerts" {
#   name = "cpu-alerts"
# }

# resource "aws_sns_topic_subscription" "cpu_alerts_email" {
#   topic_arn = aws_sns_topic.cpu_alerts.arn
#   protocol  = "email"
#   endpoint  = "zee.dar1992@gmail.com"  # replace with your email
# }


provider "aws" {
  region = "us-west-1"
}
resource "aws_instance" "docker_host" {
  ami             = "ami-073e64e4c237c08ad" # This is an Amazon Linux 2 LTS AMI. Make sure to use an updated one or the one relevant to your region.
  instance_type   = "t2.micro"

  key_name        = "your_key_name" # Ensure you have this key pair created or replace with your existing key pair name
  security_groups = [aws_security_group.allow_alb.name]
  user_data = <<-EOT
              #!/bin/bash
              yum update -y
              yum install -y docker
              systemctl start docker
              systemctl enable docker
              usermod -a -G docker ec2-user
              curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              echo "version: '3'
              services:
                fastapi-app:
                  image: zeedar/terraform-aws:latest
                  ports:
                    - '80:80'
                  environment:
                    - AWS_DEFAULT_REGION=us-west-1
                    - ES_URL=http://elasticsearch:9200
                  depends_on:
                    - elasticsearch
                elasticsearch:
                  image: docker.elastic.co/elasticsearch/elasticsearch:7.9.3
                  environment:
                    - discovery.type=single-node
                    - cluster.name=docker-cluster
                    - bootstrap.memory_lock=true
                    - ES_JAVA_OPTS=-Xms512m -Xmx512m
                  ulimits:
                    memlock:
                      soft: -1
                      hard: -1
                  ports:
                    - '9200:9200'" > /home/ec2-user/docker-compose.yml
              docker-compose -f /home/ec2-user/docker-compose.yml pull fastapi-app
              docker-compose -f /home/ec2-user/docker-compose.yml up -d
              EOT

  tags = {
    Name = "DockerHost"
  }
}


resource "aws_security_group" "allow_alb" {
  name        = "allow_docker_traffic"
  description = "Allow all inbound traffic"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


