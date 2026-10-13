# AWS region where all resources will be deployed
variable "aws_region" {
  type    = string
  default = "eu-west-3"
}

# Short trainee identifier used in resource names to keep them unique per trainee
variable "trigram" {
  type = string
  # No default — Terraform will prompt you for your trigram during apply.
  # Use 2 to 4 lowercase letters, e.g., jdo for "John Doe"

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.trigram))
    error_message = "trigram must be 2 to 4 lowercase letters (e.g. jdo)."
  }
}

# Short region token used in resource naming
variable "region_short" {
  type    = string
  default = "ew3"
}

# Mandatory project tag used by cleanup policy
variable "project_tag" {
  type    = string
  default = "cse-aws"
}

# Environment tag value
variable "environment" {
  type    = string
  default = "sandbox"
}

# VPC CIDR block
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# Public subnet CIDRs — two subnets in different Availability Zones (required by RDS)
variable "public_subnet_cidr_az1" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_cidr_az2" {
  type    = string
  default = "10.0.2.0/24"
}

variable "availability_zone_az1" {
  type    = string
  default = "eu-west-3a"
}

variable "availability_zone_az2" {
  type    = string
  default = "eu-west-3b"
}

# EC2 instance type for the app VM
variable "ec2_instance_type" {
  type    = string
  default = "t3.micro"
}

# Database configuration
variable "db_name" {
  type    = string
  default = "picturegallery"
}

variable "db_username" {
  type    = string
  default = "adminformation"
}

# Database admin password — you MUST set this. Choose a strong password and save it to your notepad.
variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

# Optional additional tags merged with baseline tags
variable "common_tags" {
  type    = map(string)
  default = {}
}

# Optional EC2 key pair name override. Leave empty to auto-generate one during apply.
variable "ec2_key_pair_name" {
  type    = string
  default = ""
}

# Optional custom AMI ID. Leave empty to use latest Amazon Linux 2023.
variable "ec2_ami_id" {
  type    = string
  default = ""
}

# Purpose token for public logo bucket name
variable "logo_bucket_purpose" {
  type    = string
  default = "logo"
}

# Purpose token for logs bucket name
variable "logs_bucket_purpose" {
  type    = string
  default = "logs"
}