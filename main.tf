# VPC — our isolated virtual network
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = local.vpc_name })
}

# Internet Gateway — allows resources in the VPC to reach the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, { Name = local.internet_gw_name })
}

# Two public subnets in different Availability Zones (required by RDS)
resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_az1
  availability_zone       = var.availability_zone_az1
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = local.subnet_az1_name })
}

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_az2
  availability_zone       = var.availability_zone_az2
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = local.subnet_az2_name })
}

# Route table — sends all traffic to the internet gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, { Name = local.route_table_name })
}

resource "aws_route_table_association" "public_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.public.id
}

# Web security group — allows HTTP, HTTPS, and SSH from anywhere
resource "aws_security_group" "web" {
  name        = local.web_sg_name
  description = "Baseline insecure web/admin access for CSE training"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.web_sg_name })
}

# DB security group — allows MySQL from anywhere (intentionally insecure)
resource "aws_security_group" "db" {
  name        = local.db_sg_name
  description = "Baseline insecure DB access for CSE training"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.db_sg_name })
}

# Generate an SSH key pair — Terraform creates the key during apply
resource "tls_private_key" "ec2_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "app_vm" {
  key_name   = local.ec2_key_pair_name
  public_key = tls_private_key.ec2_ssh.public_key_openssh

  tags = merge(local.tags, { Name = local.ec2_key_pair_name })
}

# EC2 instance — our web server with LAMP stack
resource "aws_instance" "app_vm" {
  ami                         = local.selected_ami_id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.public_az1.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = aws_key_pair.app_vm.key_name
  associate_public_ip_address = true

  # Bootstrap script: installs Apache, PHP, MySQL client, and Git
  user_data = templatefile(
    "${path.module}/ec2-init.sh.tpl",
    {
      db_host     = aws_db_instance.mysql.address
      db_name     = var.db_name
      db_user     = var.db_username
      db_password = var.db_password
    }
  )

  tags = merge(local.tags, { Name = local.ec2_name })
}

# S3 bucket for the logo — publicly readable (intentionally insecure for training)
resource "aws_s3_bucket" "logo" {
  bucket = local.logo_bucket_name
  tags   = merge(local.tags, { Name = local.logo_bucket_name, Purpose = "logo" })
}

# Disable Block Public Access so we can make objects publicly readable
resource "aws_s3_bucket_public_access_block" "logo" {
  bucket = aws_s3_bucket.logo.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Bucket policy — allows anyone to read objects (intentionally insecure)
resource "aws_s3_bucket_policy" "logo_public_read" {
  bucket = aws_s3_bucket.logo.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicReadForTraining"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "${aws_s3_bucket.logo.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.logo]
}

# S3 bucket for logs — NOT publicly accessible
resource "aws_s3_bucket" "logs" {
  bucket = local.logs_bucket_name
  tags   = merge(local.tags, { Name = local.logs_bucket_name, Purpose = "logs" })
}

# Block all public access on the logs bucket (secure by default)
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DB subnet group — RDS requires subnets in at least 2 Availability Zones
resource "aws_db_subnet_group" "main" {
  name       = local.db_subnet_group
  subnet_ids = [aws_subnet.public_az1.id, aws_subnet.public_az2.id]

  tags = merge(local.tags, { Name = local.db_subnet_group })
}

# DB parameter group — disables SSL requirement (intentionally insecure for training)
resource "aws_db_parameter_group" "mysql_insecure" {
  name   = local.db_parameter_group
  family = "mysql8.0"

  parameter {
    name  = "require_secure_transport"
    value = "OFF"
  }

  tags = merge(local.tags, { Name = local.db_parameter_group })
}

# RDS MySQL instance — publicly accessible (intentionally insecure for training)
resource "aws_db_instance" "mysql" {
  identifier             = local.db_identifier
  allocated_storage      = var.db_allocated_storage
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.mysql_insecure.name

  publicly_accessible        = true
  deletion_protection        = false
  skip_final_snapshot        = true
  delete_automated_backups   = true
  backup_retention_period    = 0
  auto_minor_version_upgrade = false
  apply_immediately          = true

  tags = merge(local.tags, { Name = local.db_identifier })
}

