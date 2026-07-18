# Infrastructure: DevOps Interview ROR App

This directory contains the Infrastructure as Code (IaC) and documentation for deploying the Ruby on Rails web application on AWS ECS Fargate using Terraform.

## Architecture Overview

```
Internet
    │
    ▼
┌─────────────────────────────────────┐
│  Application Load Balancer (ALB)    │  ◄─── Public Subnets
│  ─ Listener: HTTP:80                │
│  ─ Target Group → ECS Tasks         │
└──────────┬──────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│  ECS Fargate Cluster                │  ◄─── Private Subnets
│  ─ Task Definition:                 │
│    ├── Container: nginx (port 80)   │
│    └── Container: rails_app (3000)  │
│  ─ Service (desired_count=2)        │
└──────────┬──────────────────────────┘
           │
     ┌─────┼─────┐
     │     │     │
     ▼     ▼     ▼
┌────────┐ ┌────────┐ ┌────────────────┐
│ RDS PG │ │ S3     │ │ CloudWatch     │
│ 13.3   │ │ Bucket │ │ Logs           │
└────────┘ └────────┘ └────────────────┘
```

## Directory Structure

```
infrastructure/
├── terraform/                  # Terraform IaC code
│   ├── provider.tf            # AWS provider configuration
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Output values
│   ├── vpc.tf                 # VPC, subnets, NAT Gateway
│   ├── security_groups.tf     # Security groups
│   ├── iam.tf                 # IAM roles & policies
│   ├── ecr.tf                 # ECR repositories
│   ├── rds.tf                 # RDS PostgreSQL instance
│   ├── s3.tf                  # S3 bucket
│   ├── alb.tf                 # Application Load Balancer
│   ├── ecs.tf                 # ECS cluster, task def, service
│   ├── terraform.tfvars.example
│   └── .gitignore
├── diagrams/                   # Architecture diagrams
│   └── architecture.md        # Mermaid architecture diagram
└── README.md                  # This file
```

## Prerequisites

1. **AWS Account** with permissions to create all resources
2. **AWS CLI** installed and configured (`aws configure`)
3. **Terraform** v1.5+ installed
4. **Docker** installed (for local testing)
5. **GitHub account** with the forked repository

## Deployment Steps

### Step 1: Fork the Repository

Fork the original repository to your GitHub account:
```bash
# Clone your fork locally
git clone https://github.com/<your-username>/DevOps-Interview-ROR-App.git
cd DevOps-Interview-ROR-App
```

### Step 2: Add IaC Code

Copy the `infrastructure/` folder from this repository into your forked project root.

### Step 3: Configure Terraform Variables

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set your values:
```hcl
aws_region      = "us-east-2"
environment     = "production"
project_name    = "ror-app"
rds_password    = "YourSecurePassword123"
rds_username    = "postgres"
rds_db_name     = "rails"
```

### Step 4: Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

After apply completes, note the output values:
- `alb_dns_name` — URL to access the application
- `ecr_rails_app_url` — ECR repo for Rails image
- `ecr_nginx_url` — ECR repo for Nginx image
- `rds_hostname` — RDS endpoint for database connection
- `s3_bucket_name` — S3 bucket name

### Step 5: Configure GitHub Secrets

In your GitHub repository, go to **Settings → Secrets and variables → Actions** and add:

| Secret Name | Value |
|-------------|-------|
| `AWS_ACCESS_KEY_ID` | Your AWS access key |
| `AWS_SECRET_ACCESS_KEY` | Your AWS secret key |
| `AWS_REGION` | `us-east-2` |

### Step 6: Push Code to Trigger CI/CD

```bash
git add .
git commit -m "Add infrastructure code and CI/CD"
git push origin main
```

GitHub Actions will automatically:
1. Build the Rails app Docker image
2. Build the Nginx Docker image (with ECS-specific config)
3. Push both images to their respective ECR repositories
4. Force a new deployment of the ECS service

### Step 7: Verify Deployment

Visit the ALB DNS name in your browser:
```
http://<alb_dns_name>
```

Check ECS service status:
```bash
aws ecs describe-services --cluster ror-app-production-cluster --services ror-app-production-service
```

### Step 8: Clean Up

To destroy all resources when done:
```bash
cd infrastructure/terraform
terraform destroy -auto-approve
```

## Environment Variables

The application requires the following environment variables, automatically injected by ECS:

| Variable | Source | Description |
|----------|--------|-------------|
| `RDS_DB_NAME` | Terraform variable | PostgreSQL database name |
| `RDS_USERNAME` | Terraform variable | Database master username |
| `RDS_PASSWORD` | Terraform variable | Database master password |
| `RDS_HOSTNAME` | RDS endpoint | Database host (auto-resolved) |
| `RDS_PORT` | Terraform variable | Database port (5432) |
| `S3_BUCKET_NAME` | Terraform resource | S3 bucket for uploads |
| `S3_REGION_NAME` | AWS region | AWS region name |
| `LB_ENDPOINT` | ALB DNS | Load balancer URL |
| `RAILS_ENV` | Hardcoded | production |
| `RAILS_LOG_TO_STDOUT` | Hardcoded | true |

## Security Best Practices

1. **IAM Roles instead of Keys** — ECS tasks use IAM roles (not AccessKey/SecretKey) for S3 access
2. **Private Subnets** — ECS tasks and RDS are in private subnets, inaccessible from internet
3. **Security Groups** — Least privilege: ALB → ECS → RDS only
4. **RDS Encryption** — Storage encryption enabled
5. **S3 Block Public Access** — All public access blocked
6. **CloudWatch Logs** — Container logs stored with 30-day retention
7. **ECR Image Scanning** — Automatic vulnerability scanning on push
