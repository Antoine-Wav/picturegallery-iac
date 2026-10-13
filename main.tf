data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  name_prefix     = "cse-sbx-${var.trigram}-${var.region_short}"
  selected_ami_id = var.ec2_ami_id != "" ? var.ec2_ami_id : data.aws_ami.amazon_linux_2023.id

  tags = merge(
    {
      Project     = var.project_tag
      Environment = var.environment
      Trainee     = var.trigram
      ManagedBy   = "terraform"
    },
    var.common_tags
  )

  # Resource names built from the naming convention
  vpc_name                    = "${local.name_prefix}-vpc-main-01"
  subnet_az1_name             = "${local.name_prefix}-subnet-public-01"
  subnet_az2_name             = "${local.name_prefix}-subnet-public-02"
  internet_gw_name            = "${local.name_prefix}-igw-main-01"
  route_table_name            = "${local.name_prefix}-rt-public-01"
  web_sg_name                 = "${local.name_prefix}-sg-web-01"
  db_sg_name                  = "${local.name_prefix}-sg-db-01"
  ec2_name                    = "${local.name_prefix}-ec2-app-01"
  generated_ec2_key_pair_name = "${local.name_prefix}-keypair-app-01"
  ec2_key_pair_name           = var.ec2_key_pair_name != "" ? var.ec2_key_pair_name : local.generated_ec2_key_pair_name
  db_subnet_group             = "${local.name_prefix}-dbsubnet-main-01"
  db_parameter_group          = "${local.name_prefix}-dbparam-mysql-01"
  db_identifier               = "${local.name_prefix}-mysql-01"
  logo_bucket_name            = lower("${local.name_prefix}-${var.logo_bucket_purpose}-${data.aws_caller_identity.current.account_id}")
  logs_bucket_name            = lower("${local.name_prefix}-${var.logs_bucket_purpose}-${data.aws_caller_identity.current.account_id}")
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

