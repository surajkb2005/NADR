terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# 1. Define your AWS Region
provider "aws" {
  region = "us-east-1" # You can change this to your preferred region (e.g., us-west-2, ap-south-1)
}

# 2. Automatically find the latest official Ubuntu 22.04 LTS image
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 3. The "Sec" in DevSecOps: Build the Firewall (Security Group)
resource "aws_security_group" "stellar_sg" {
  name        = "stellar-route-prod-sg"
  description = "Allow HTTP, HTTPS, and SSH traffic"

  # SSH (So you can log in)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP (For Nginx routing)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (For your secure SSL padlock)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: Allow server to talk to the internet (to download Docker)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 4. Rent the Server (EC2 Instance)
resource "aws_instance" "stellar_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small" 
  
  # CRITICAL: This must match the exact name of the SSH Key Pair you created in AWS!
  key_name      = "stellar-key" 
  
  vpc_security_group_ids = [aws_security_group.stellar_sg.id]

  tags = {
    Name = "StellarRoute-Production"
  }
}

# 5. Print the IP address to the terminal when finished
output "server_public_ip" {
  value       = aws_instance.stellar_server.public_ip
  description = "The public IP address of your new AWS server"
}