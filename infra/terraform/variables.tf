variable "aws_account_id" {
  description = "The only AWS account this stack may touch."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be 12 digits."
  }
}

variable "aws_region" {
  description = "AWS region of the stack."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Prefix of resource names and the Project tag."
  type        = string
  default     = "nba-sim"
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "prod"
}

variable "instance_type" {
  description = "EC2 instance type. Graviton (arm64) to match the AMI."
  type        = string
  default     = "t4g.micro"
  validation {
    condition     = can(regex("^(t4g|m7g|c7g|m8g|c8g)[.]", var.instance_type))
    error_message = "instance_type must be a Graviton (arm64) type, to match the AMI."
  }
}

variable "root_volume_gb" {
  description = "Size of the root EBS volume in GiB."
  type        = number
  default     = 16
}

variable "backup_interval_minutes" {
  description = "How often the instance uploads a SQLite snapshot to S3."
  type        = number
  default     = 15
}

variable "backup_retention_days" {
  description = "Days before S3 deletes a snapshot."
  type        = number
  default     = 90
}
