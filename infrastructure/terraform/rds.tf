resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "DB subnet group for RDS PostgreSQL"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_parameter_group" "postgres" {
  name        = "${var.project_name}-${var.environment}-pg18"
  family      = "postgres18"
  description = "Parameter group for PostgreSQL 18.3"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

data "aws_rds_engine_version" "postgres" {
  engine             = "postgres"
  preferred_versions = ["18.3", "18.2", "18.1", "18"]
}

resource "aws_db_instance" "main" {
  identifier             = "${var.project_name}-${var.environment}-db"
  engine                 = data.aws_rds_engine_version.postgres.engine
  engine_version         = data.aws_rds_engine_version.postgres.version
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  storage_type           = "gp2"
  db_name                = var.rds_db_name
  username               = var.rds_username
  password               = var.rds_password
  port                   = var.rds_port
  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = false
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  multi_az               = false
  publicly_accessible    = false
  storage_encrypted      = true
  deletion_protection    = false

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
