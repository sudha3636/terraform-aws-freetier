# AWS 3-Tier Infrastructure with Terraform

A production-style cloud infrastructure project built on AWS using Terraform. This project provisions a complete 3-tier architecture — compute, database, and storage — with security, monitoring, and cost efficiency built in from the ground up. The application runs inside a Docker container on EC2, connects to a MySQL database on RDS, stores assets in S3, and is monitored through CloudWatch dashboards and alarms.

---

## Architecture

```
                        Internet
                            │
                   ┌────────▼────────┐
                   │  EC2 t2.micro   │  ← public subnet (10.0.1.0/24)
                   │  Docker         │
                   │  Node.js App    │
                   └────────┬────────┘
                            │ port 3306 only
                   ┌────────▼────────┐
                   │  RDS MySQL 8.0  │  ← private subnet (10.0.2.0/24)
                   │  db.t3.micro    │     private subnet (10.0.3.0/24)
                   └─────────────────┘

        S3 Bucket ───────────────────── CloudWatch
        (assets + encryption)           (dashboards + alarms)

        SSM Parameter Store ──────────── IAM Roles
        (DB credentials)                (least privilege)
```

---

## What This Project Provisions

When you run `terraform apply`, the following AWS resources are created automatically:

- Custom VPC with public and private subnets across two availability zones
- EC2 t2.micro instance running a Dockerized Node.js web application
- RDS MySQL 8.0 on db.t3.micro in a private subnet with no public internet exposure
- S3 bucket with server-side encryption, versioning, and public access fully blocked
- CloudWatch dashboards tracking EC2 CPU, RDS CPU, RDS storage, and network metrics
- CloudWatch alarms for EC2 CPU, RDS CPU, and RDS low storage with automated alerting
- IAM roles and instance profiles following least-privilege access principles
- AWS SSM Parameter Store for secure credential management — no hardcoded secrets anywhere

The Node.js application connects to MySQL on RDS, logs every visitor's IP address, and displays a live visit counter on the webpage — demonstrating end-to-end connectivity across all three tiers.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Infrastructure as Code | Terraform |
| Cloud Provider | AWS (ap-south-1 Mumbai) |
| Compute | EC2 t2.micro |
| Database | RDS MySQL 8.0 on db.t3.micro |
| Storage | S3 with SSE-S3 encryption + versioning |
| Containerization | Docker |
| Application | Node.js |
| Monitoring | CloudWatch Dashboards + Metric Alarms |
| Secret Management | AWS SSM Parameter Store (SecureString) |
| Access Control | IAM Roles + Instance Profile |
| Bootstrapping | EC2 user_data script |

---

## Project Structure

```
terraform-aws-freetier/
├── provider.tf       # AWS + random provider configuration
├── main.tf           # All AWS resource definitions
├── variables.tf      # Input variables with defaults
├── outputs.tf        # Output values printed after apply
├── userdata.sh       # EC2 bootstrap: installs Docker, fetches SSM creds, runs app
└── README.md
```

---

## Prerequisites

Before running this project, make sure you have:

- [Terraform](https://developer.hashicorp.com/terraform/install) v1.3.0 or higher
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with your credentials (`aws configure`)
- An SSH key pair at `~/.ssh/id_rsa.pub` — generate with `ssh-keygen -t rsa -b 4096`
- An AWS account with appropriate IAM permissions

---

## How to Deploy

**Step 1 — Clone the repository**

```bash
git clone https://github.com/sudha3636/terraform-aws-freetier
cd terraform-aws-freetier
```

**Step 2 — Initialize Terraform**

```bash
terraform init
```

**Step 3 — Preview resources to be created**

```bash
terraform plan
```

**Step 4 — Deploy**

```bash
terraform apply
```

Type `yes` when prompted. Full deployment takes around 10–12 minutes — RDS provisioning accounts for most of that time.

**Step 5 — Access the application**

After apply completes, Terraform prints output values including the app URL:

```
app_url = "http://<your-ec2-public-ip>"
```

Open that in a browser. You will see the application running with a live visit counter pulled from the RDS database.

---

## Security Design

- RDS is deployed in a **private subnet** with no public accessibility — the security group only allows port 3306 traffic originating from the EC2 security group, not from any IP range
- Database credentials are stored in **AWS SSM Parameter Store as SecureString** using the AWS managed KMS key — credentials are fetched at runtime and never appear in code or environment files
- S3 bucket has **all public access blocked** with server-side encryption enabled using AES-256
- IAM roles follow **least privilege** — EC2 only has CloudWatch agent, S3 read-only, and SSM read-only permissions
- SSH access to EC2 can be locked to a specific IP by updating the `my_ip` variable in `variables.tf`

---

## Infrastructure Design Decisions

- **t2.micro / db.t3.micro** — right-sized for a demo workload; easily scaled by changing the `instance_type` and `db_instance_class` variables
- **Single AZ deployment** — appropriate for non-production; set `multi_az = true` in the RDS block for production-grade failover
- **No NAT Gateway** — intentionally avoided to reduce data transfer costs; add for production workloads that need outbound internet from private subnets
- **SSM Parameter Store over Secrets Manager** — Standard tier SSM used for credential storage; migrate to Secrets Manager for automatic rotation in production
- **No ALB** — EC2 public IP used directly for simplicity; replace with an Application Load Balancer for SSL termination and high availability in production
- **backup_retention_period = 0** — automated backups disabled for demo; set to 7 or more days for production

---

## Cost Optimization

This project is designed with cost efficiency in mind:

- Right-sized compute and database instances for the workload
- Storage autoscaling disabled on RDS to prevent unexpected cost growth
- No NAT Gateway — avoids per-hour charges by keeping the app tier in a public subnet
- No Elastic IP — uses auto-assigned public IP to avoid charges for unused addresses
- Multi-AZ disabled for non-production environment — can be enabled per environment using a Terraform variable
- S3 lifecycle policies can be added to transition infrequent objects to cheaper storage classes

---

## How to Extend This Project

This project is intentionally kept simple to demonstrate core concepts. Production-ready extensions include:

- Add an **Application Load Balancer** with SSL/TLS via ACM for HTTPS support
- Enable **RDS Multi-AZ** for automatic failover and production-grade availability
- Add an **Auto Scaling Group** behind the ALB for the EC2 compute layer
- Integrate a **GitHub Actions CI/CD pipeline** to auto-deploy on every code push
- Add **Terraform remote state** using S3 backend + DynamoDB for state locking in team environments
- Enable **RDS automated backups** with point-in-time recovery
- Add **AWS WAF** to the ALB for application-layer protection
- Use **Terraform workspaces** to manage dev, staging, and prod from the same codebase

---

## Destroying Resources

When done, tear everything down with:

```bash
terraform destroy
```

Type `yes` to confirm. Always verify in the AWS Console that no resources remain.

---

## What I Learned

- Writing modular Terraform code using variables, outputs, and providers
- Designing a secure VPC with proper public and private subnet separation
- Connecting EC2 to RDS securely using security group references instead of CIDR-based rules
- Using SSM Parameter Store to eliminate hardcoded credentials from application and infrastructure code
- Bootstrapping EC2 instances using user_data scripts with Docker and runtime secret injection
- Setting up CloudWatch dashboards and metric alarms for proactive infrastructure monitoring
- Managing the full infrastructure lifecycle with Terraform plan, apply, and destroy

---

## Screenshots

| Screenshot | Description |
|------------|-------------|
| "C:\Users\sudha\OneDrive\Pictures\Screenshots\Website output.png" | Application running in browser with visit counter |
| "C:\Users\sudha\OneDrive\Pictures\Screenshots\EC2-demo-app-server.png" | EC2 instance running in AWS Console |
| "C:\Users\sudha\OneDrive\Pictures\Screenshots\RDS DB-demo-app-mysql.png"| RDS instance available in AWS Console |
| "C:\Users\sudha\OneDrive\Pictures\Screenshots\Cloudwatch dashboard.png"| CloudWatch dashboard with live metrics |
| "C:\Users\sudha\OneDrive\Pictures\Screenshots\terraform state lists.png" | Terraform apply output in terminal |
| "C:\Users\sudha\OneDrive\Pictures\Screenshots\SSM Parameter Store.png" | SSM Parameter Store showing DB credentials |

---

## Author

**Sudha Hiremath**
Cloud & DevOps Engineer | AWS Certified Solutions Architect – Associate | AWS Certified Cloud Practitioner

- LinkedIn: [linkedin.com/in/sudha-hiremath](https://linkedin.com/in/sudha-hiremath)
- GitHub: [github.com/sudha3636](https://github.com/sudha3636)
