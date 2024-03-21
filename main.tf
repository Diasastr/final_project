terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
}

variable "jenkins_private_ip" {
  type = list(string)
  default = ["0.0.0.0/32"]
}

variable "jenkins_public_ip" {
  type = list(string)
  default = ["0.0.0.0/32"]
}

variable "my_tags" {
  default = ["postgresql", "gitea1", "gitea2", "monitoring"]
}

variable "instance_count" {
  default = 4
}

variable "public_subnet_id" {
  default = "public-1"
}

variable "vpc_id" {
  default = "vpc-diana"
}

variable "instance_connect_ssh_cidr" {
  description = "CIDR blocks for SSH access to Jenkins."
  type        = list(string)
  default     = ["13.48.4.200/30"]
}

resource "aws_instance" "gitea_instances" {
  ami             = "ami-079ae45378903f993"
  count           = var.instance_count
  subnet_id       = var.public_subnet_id
  instance_type   = "t3.small"
  key_name        = "jenkins-key-pair"  # Replace with your key pair name
  vpc_security_group_ids = [aws_security_group.tf_sec_gr.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_ecr_profile.name

  tags = {
    Name = element(var.my_tags, count.index)
    stack = "gitea_stack"
    environment = "development"
  }

  user_data = <<-EOF
                #! /bin/bash
                sudo yum update -y
                EOF
}


resource "aws_iam_policy" "ecr_access_policy" {
  name        = "ECRAccessPolicy"
  description = "Policy for allowing access to ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetLifecyclePolicy",
          "ecr:GetLifecyclePolicyPreview",
          "ecr:ListTagsForResource",
          "ecr:DescribeImageScanFindings",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "ec2_ecr_role" {
  name = "EC2ECRRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_access_policy_attachment" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = aws_iam_policy.ecr_access_policy.arn
}

resource "aws_iam_instance_profile" "ec2_ecr_profile" {
  name = "EC2ECRInstanceProfile"
  role = aws_iam_role.ec2_ecr_role.name
}


resource "aws_security_group" "tf_sec_gr" {
  name = "tf-sec-gr-diana"
  vpc_id = var.vpc_id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.instance_connect_ssh_cidr
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.jenkins_private_ip
  }

   ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.jenkins_public_ip
  }

  # Gitea HTTP/HTTPS access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    protocol    = "tcp"
    to_port     = 5000
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    protocol    = "tcp"
    to_port     = 3000
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # PostgreSQL access
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress to allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "gitea_instance_ips" {
  value = aws_instance.gitea_instances.*.public_ip
}

output "gitea1_ip" {
  value = "http://${aws_instance.gitea_instances[1].public_ip}:3000"
}

output "gitea2_ip" {
  value = "http://${aws_instance.gitea_instances[2].public_ip}:3000"
}

output "grafana_ip" {
  value = "http://${aws_instance.gitea_instances[3].public_ip}" # Adjust if the instance index for Grafana changes
}

output "postgresql_private_ip" {
  value = aws_instance.gitea_instances[0].private_ip # Adjust if the instance index for PostgreSQL changes
}
