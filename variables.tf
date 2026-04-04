variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"

}

variable "project_name" {
  description = "AWS free tier"
  type        = string
  default     = "demo-app"

}
variable "ami_id" {
  description = "Ubuntu 22.04 AMI for ap-south-1"
  type        = string
  default     = "ami-0dee22c13ea7a9a67"

}
variable "instance_type" {
  description = "EC2 instance type - free tier"
  type        = string
  default     = "t3.micro"

}
variable "my_ip" {
  description = "Your local IP for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  default     = "" # change this!
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class - free tier"
  type        = string
  default     = "db.t3.micro" # free tier eligible
}

variable "db_engine_version" {
  description = "MySQL version"
  type        = string
  default     = "8.0"
}