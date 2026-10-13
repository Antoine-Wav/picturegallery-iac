output "account_id" {
  description = "Current AWS account ID."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS region where the deployment will happen."
  value       = var.aws_region
}

output "name_prefix" {
  description = "The naming prefix used in resources, will be unique by trainee."
  value       = local.name_prefix
}

output "ec2_instance_id" {
  description = "Application VM instance ID."
  value       = aws_instance.app_vm.id
}

output "ec2_public_ip" {
  description = "Application VM public IP."
  value       = aws_instance.app_vm.public_ip
}

output "ec2_public_dns" {
  description = "Application VM public DNS."
  value       = aws_instance.app_vm.public_dns
}

output "application_url" {
  description = "This builds the base URL for the gallery app."
  value       = "http://${aws_instance.app_vm.public_ip}/picturegallery"
}

output "logo_bucket_name" {
  description = "S3 bucket for public logo."
  value       = aws_s3_bucket.logo.bucket
}

output "logs_bucket_name" {
  description = "S3 bucket for collecting logs."
  value       = aws_s3_bucket.logs.bucket
}

output "rds_endpoint" {
  description = "RDS endpoint for application DB connectivity."
  value       = aws_db_instance.mysql.endpoint
}

output "rds_port" {
  description = "RDS MySQL port."
  value       = aws_db_instance.mysql.port
}

output "cleanup_selector" {
  description = "This will be used for cleaning the sandbox ressources. Do not modify"
  value       = "Project=${var.project_tag}"
}

output "ec2_key_pair_name" {
  description = "EC2 key pair name used to access the VM."
  value       = aws_key_pair.app_vm.key_name
}

output "ec2_private_key_pem" {
  description = "Generated private key for SSH access to app VM. Handle with caution !"
  value       = tls_private_key.ec2_ssh.private_key_pem
  sensitive   = true
}