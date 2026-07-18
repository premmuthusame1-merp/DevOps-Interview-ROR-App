output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "ecr_rails_app_url" {
  description = "ECR repository URL for the Rails app image"
  value       = aws_ecr_repository.rails_app.repository_url
}

output "ecr_nginx_url" {
  description = "ECR repository URL for the Nginx image"
  value       = aws_ecr_repository.nginx.repository_url
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_hostname" {
  description = "RDS hostname (from endpoint)"
  value       = split(":", aws_db_instance.main.endpoint)[0]
}

output "s3_bucket_name" {
  description = "S3 bucket name for application storage"
  value       = aws_s3_bucket.app.bucket
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.main.name
}
