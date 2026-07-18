variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "ror-app"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "rds_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "rails"
}

variable "rds_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "rds_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "rds_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS Fargate task"
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Memory in MB for ECS Fargate task"
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "rails_app_image_tag" {
  description = "Docker image tag for the Rails app"
  type        = string
  default     = "latest"
}

variable "nginx_image_tag" {
  description = "Docker image tag for Nginx"
  type        = string
  default     = "latest"
}
