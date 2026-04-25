output "alb_dns_name" {
  description = "Public DNS name of the ALB. Hit this with curl/browser."
  value       = aws_lb.app.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone of the ALB (use for an Alias record in Route53)."
  value       = aws_lb.app.zone_id
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  value = aws_subnet.private_data[*].id
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "db_endpoint" {
  description = "RDS writer endpoint (private, only reachable from app SG)."
  value       = aws_db_instance.app.address
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials."
  value       = aws_secretsmanager_secret.db.arn
}

output "db_secret_name" {
  description = "Name of the Secrets Manager secret holding DB credentials."
  value       = aws_secretsmanager_secret.db.name
}

output "ssm_session_command" {
  description = "Copy/paste this to shell into a private app instance via SSM (no SSH needed)."
  value       = "aws ssm start-session --region ${var.region} --target $(aws ec2 describe-instances --region ${var.region} --filters 'Name=tag:aws:autoscaling:groupName,Values=${aws_autoscaling_group.app.name}' 'Name=instance-state-name,Values=running' --query 'Reservations[0].Instances[0].InstanceId' --output text)"
}
