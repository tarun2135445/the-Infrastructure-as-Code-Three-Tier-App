###############################################################################
# RDS Postgres.
#
# - Lives in the *data* subnets, which have no inbound route from outside
#   the VPC and the SG only allows app-tier traffic.
# - Multi-AZ: a synchronous standby in a second AZ. RDS handles the
#   failover; the endpoint stays the same.
# - Storage encryption is on by default with the AWS-managed key.
# - Performance Insights on so we can debug query problems via the console.
###############################################################################

resource "aws_db_subnet_group" "app" {
  name_prefix = "${local.name_prefix}-db-"
  description = "Private data subnets for ${local.name_prefix} RDS"
  subnet_ids  = aws_subnet.private_data[*].id

  tags = {
    Name = "${local.name_prefix}-db-subnets"
  }
}

resource "aws_db_parameter_group" "app" {
  name_prefix = "${local.name_prefix}-pg-"
  family      = "postgres16"
  description = "Postgres 16 parameter group for ${local.name_prefix}"

  parameter {
    name  = "log_min_duration_statement"
    value = "500" # log statements > 500ms
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "app" {
  identifier     = "${local.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  parameter_group_name = aws_db_parameter_group.app.name

  backup_retention_period = var.db_backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:30-Mon:05:30"

  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = !var.db_deletion_protection
  final_snapshot_identifier = var.db_deletion_protection ? "${local.name_prefix}-db-final-${formatdate("YYYYMMDDhhmmss", timestamp())}" : null

  apply_immediately = true

  # The password rotates only via random_password lifecycle, not on every plan.
  lifecycle {
    ignore_changes = [
      final_snapshot_identifier, # changes every plan due to timestamp()
    ]
  }
}
