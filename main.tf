terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

resource "aws_db_instance" "task3_database" {
  instance_class          = "db.t2.micro"
  engine                  = "mysql"
  engine_version          = "5.7"
  allocated_storage       = 20
  identifier              = "task3db"
  name                    = "task3db"
  username                = "admin"
  password                = "admin123"
  apply_immediately       = "true"
  db_subnet_group_name    = aws_db_subnet_group.rds-db-subnet.name
  vpc_security_group_ids  = [aws_security_group.rds-sg.id]
}

resource "aws_db_subnet_group" "rds-db-subnet" {
  name = "rds-db-subnet"
  subnet_ids = data.aws_subnet_ids.default.ids
}

resource "aws_security_group" "rds-sg" {
  name = "rds-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_configuration" "task3" {
  image_id = "ami-0b499c10196d0167b"
  instance_type = "t2.micro"
   
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello world" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
  security_groups = [aws_security_group.instance.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "task3" {
  launch_configuration = aws_launch_configuration.task3.name

  vpc_zone_identifier = data.aws_subnet_ids.default.ids
  min_size = 2
  max_size = 10
  tag {
    key = "Name"
    value = "terraform-asg-task3"
    propagate_at_launch = true
  }

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"
}

resource "aws_lb" "task3" {
  name = "terraform-asg-task3"
  load_balancer_type = "application"
  subnets = data.aws_subnet_ids.default.ids
  security_groups = [aws_security_group.alb.id]
}

resource "aws_security_group" "alb" {
  name = "terraform-task3-alb"

  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
      from_port = 80
      to_port = 80
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group" "instance" {
  name = "terraform-task3-instance"

  ingress {
      from_port = var.server_port
      to_port = var.server_port
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.task3.arn 
  port = 80
  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn 
  priority = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-task3"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol ="HTTP"
    matcher = "200"
    interval = 30
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name = "api-gateway"
  description = "Online sample REST API"
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id = aws_api_gateway_rest_api.api.root_resource_id
  path_part = "categories"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  integration_http_method = "GET"
  type = "HTTP_PROXY"
  uri = "https://gorest.co.in/public-api/categories"
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name = "dev"

  lifecycle {
    create_before_destroy = true
  }
}

variable "server_port" {
  description = "Port to run at"
  type = number
  default = 8080
}

output "alb_dns_name" {
  value = aws_lb.task3.dns_name
  description = "Domain name of the load balancer"
}

output "db_instance_endpoint" {
  value = aws_db_instance.task3_database.endpoint
  description = "Endpoint of DB instance"
}

output "api_resource_url" {
  value = join("/", [aws_api_gateway_deployment.deployment.invoke_url, aws_api_gateway_resource.resource.path_part])
  description = "URL of the resource from API"
}
