###############################################################################
# Identity
###############################################################################

variable "project" {
  description = "Short project name. Used as a prefix on every resource name."
  type        = string
  default     = "aws-portfolio"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}$", var.project))
    error_message = "project must be lowercase alphanumeric with dashes, 2-25 chars."
  }
}

variable "environment" {
  description = "Environment label. Stamped into tags and resource names."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Owner tag — who to ask about this stack."
  type        = string
  default     = "platform"
}

###############################################################################
# Region & networking
###############################################################################

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Top-level CIDR for the VPC. /16 leaves room for plenty of /24 subnets."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to span. Two is the minimum for HA + RDS Multi-AZ."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    If true, place one NAT Gateway in the first public subnet and route all
    private subnets through it. Cheaper (~$32/mo vs ~$64/mo for two) but a
    single-AZ failure cuts internet egress for private subnets in the other
    AZ. Acceptable for dev; flip to false for prod.
  EOT
  type        = bool
  default     = true
}

###############################################################################
# Compute
###############################################################################

variable "instance_type" {
  description = "EC2 instance type for the app tier."
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum instances in the ASG."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum instances in the ASG."
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Initial desired instances in the ASG."
  type        = number
  default     = 2
}

variable "app_port" {
  description = "Port the application listens on inside the instance."
  type        = number
  default     = 8080
}

###############################################################################
# Database
###############################################################################

variable "db_engine_version" {
  description = "Postgres engine version."
  type        = string
  default     = "16.3"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Initial RDS storage in GB. Autoscales up to db_max_allocated_storage."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GB."
  type        = number
  default     = 100
}

variable "db_multi_az" {
  description = "Run RDS Multi-AZ. Required for prod-grade HA; doubles cost."
  type        = bool
  default     = true
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the DB. The password is generated and stored in Secrets Manager."
  type        = string
  default     = "appadmin"
}

variable "db_backup_retention_days" {
  description = "Days to retain automated DB backups."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Block accidental deletion of the DB. Turn on for prod."
  type        = bool
  default     = false
}

###############################################################################
# Observability
###############################################################################

variable "alarm_cpu_threshold" {
  description = "CPU utilization (%) that triggers the high-CPU alarm on the ASG."
  type        = number
  default     = 75
}

variable "alarm_email" {
  description = "If set, an SNS topic is created and this email is subscribed for alarm notifications."
  type        = string
  default     = ""
}
