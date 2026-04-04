data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  project_name_safe_raw = replace(replace(lower(var.project_name), " ", "-"), "_", "-")
  project_name_safe = can(regex("^[a-z].*", local.project_name_safe_raw)) ? local.project_name_safe_raw : "a${local.project_name_safe_raw}"
}

resource "aws_security_group" "app_sg" {
  description = "Allow HTTP and SSH traffic"
  name        = "${var.project_name}-app-sg"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name    = "${var.project_name}-app-sg"
    Project = var.project_name
  }
}
resource "aws_key_pair" "app_key" {
  key_name   = "${var.project_name}-key"
  public_key = file("~/.ssh/id_rsa.pub")

  tags = {
    Name = "${var.project_name}-key"
  }
}
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_instance" "app_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = aws_key_pair.app_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name


  user_data = file("userdata.sh")

  root_block_device {
    volume_size           = 8
    volume_type           = "gp2"
    delete_on_termination = true
  }
  tags = {
    Name        = "${var.project_name}-server"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket" "app_bucket" {
  bucket = "${local.project_name_safe}-assets-${random_id.suffix.hex}"


  tags = {
    Name    = "${var.project_name}-bucket"
    Project = var.project_name
  }
}
resource "random_id" "suffix" {
  byte_length = 4
}
resource "aws_s3_bucket_versioning" "app_bucket_versioning" {
  bucket = aws_s3_bucket.app_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app_bucket" {
  bucket                  = aws_s3_bucket.app_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# ================================================================
# FIX: Replace your aws_cloudwatch_dashboard block in main.tf
# with this corrected version (added region to all widgets)
# ================================================================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU Utilization"
          region = var.aws_region
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/EC2", "CPUUtilization",
            "InstanceId", aws_instance.app_server.id]
          ]
          annotations = {
            horizontal = []
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "RDS CPU Utilization"
          region = var.aws_region
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "CPUUtilization",
            "DBInstanceIdentifier", aws_db_instance.mysql.id]
          ]
          annotations = {
            horizontal = []
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS Free Storage Space"
          region = var.aws_region
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "FreeStorageSpace",
            "DBInstanceIdentifier", aws_db_instance.mysql.id]
          ]
          annotations = {
            horizontal = []
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "EC2 Network In/Out"
          region = var.aws_region
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/EC2", "NetworkIn",
            "InstanceId", aws_instance.app_server.id],
            ["AWS/EC2", "NetworkOut",
            "InstanceId", aws_instance.app_server.id]
          ]
          annotations = {
            horizontal = []
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EC2 CPU above 80%"

  dimensions = {
    InstanceId = aws_instance.app_server.id
  }

  tags = {
    Project = var.project_name
  }
}

# ─── RDS SUBNET GROUP ──────────────────────────────────────
# Uses default VPC subnets for RDS
resource "aws_db_subnet_group" "rds_subnet_group" {
  name = "${local.project_name_safe}-rds-subnet-group"
  subnet_ids = [
    data.aws_subnets.default.ids[0],
    data.aws_subnets.default.ids[1]
  ]

  tags = {
    Name    = "${local.project_name_safe}-rds-subnet-group"
    Project = var.project_name
  }
}

# ─── RDS SECURITY GROUP ────────────────────────────────────
# Only allows MySQL traffic FROM the EC2 security group
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow MySQL only from EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id] # only EC2 can access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-rds-sg"
    Project = var.project_name
  }
}

# ─── RDS PARAMETER GROUP ───────────────────────────────────
# Custom MySQL settings
resource "aws_db_parameter_group" "mysql" {
  name   = "${local.project_name_safe}-mysql-params"
  family = "mysql8.0"

  parameter {
    name  = "max_connections"
    value = "100"
  }

  parameter {
    name  = "innodb_buffer_pool_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  tags = {
    Name    = "${local.project_name_safe}-mysql-params"
    Project = var.project_name
  }
}

# ─── RDS MYSQL INSTANCE (FREE TIER) ────────────────────────
resource "aws_db_instance" "mysql" {
  identifier = "${local.project_name_safe}-mysql"

  # Engine
  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class # db.t3.micro = FREE

  # Storage - 20GB free tier
  allocated_storage     = 20
  max_allocated_storage = 20 # no auto-scaling storage (avoids cost)
  storage_type          = "gp2"
  storage_encrypted     = true

  # Database credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false # private only - more secure

  # Free tier settings
  multi_az             = false # multi-az costs money - keep false
  parameter_group_name = aws_db_parameter_group.mysql.name

  # Backup - 0 days = no automated backups (saves free tier storage)
  backup_retention_period = 0
  skip_final_snapshot     = true # no snapshot on delete = no cost
  deletion_protection     = false

  # Monitoring - basic only (free)
  monitoring_interval = 0 # enhanced monitoring costs money - keep 0

  tags = {
    Name        = "${var.project_name}-mysql"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

# ─── CLOUDWATCH ALARM FOR RDS ──────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU above 80%"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.mysql.id
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.project_name}-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2000000000 # alert when < 2GB free
  alarm_description   = "RDS free storage below 2GB"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.mysql.id
  }

  tags = {
    Project = var.project_name
  }
}

# ─── SSM PARAMETER STORE ───────────────────────────────────
# Store DB credentials securely (free service)
resource "aws_ssm_parameter" "db_host" {
  name  = "/${var.project_name}/db/host"
  type  = "String"
  tier  = "Standard"
  value = aws_db_instance.mysql.address
  depends_on = [aws_db_instance.mysql]  # ← add this
  tags = { Project = var.project_name }
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/${var.project_name}/db/name"
  type  = "String"
  tier  = "Standard"
  value = var.db_name
  depends_on = [aws_db_instance.mysql]  # ← add this
  tags = { Project = var.project_name }
}

resource "aws_ssm_parameter" "db_user" {
  name  = "/${var.project_name}/db/username"
  type  = "SecureString"
  tier  = "Standard"
  value = var.db_username
  depends_on = [aws_db_instance.mysql]  # ← add this
  tags = { Project = var.project_name }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project_name}/db/password"
  type  = "SecureString"
  tier  = "Standard"
  value = var.db_password
  depends_on = [aws_db_instance.mysql]  # ← add this
  tags = { Project = var.project_name }
}






