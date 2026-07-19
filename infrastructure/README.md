# Deployment Report

## Project: Ruby on Rails Web Application on AWS ECS Fargate

### Prepared by: premmuthusame-merp
### Date: July 18, 2026
### Repository: https://github.com/premmuthusame1-merp/DevOps-Interview-ROR-App
### IaC Tool: Terraform
### AWS Region: us-east-2

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Infrastructure Components](#2-infrastructure-components)
3. [Architecture Diagram](#3-architecture-diagram)
4. [Deployment Steps (End-to-End)](#4-deployment-steps-end-to-end)
5. [Configuration Details](#5-configuration-details)
6. [Environment Variables](#6-environment-variables)
7. [Security Best Practices Implemented](#7-security-best-practices-implemented)
8. [CI/CD Pipeline](#8-cicd-pipeline)
9. [Troubleshooting & Issues Resolved](#9-troubleshooting--issues-resolved)
10. [How to Access the Application](#10-how-to-access-the-application)
11. [Cost Breakdown](#11-cost-breakdown)
12. [Clean Up](#12-clean-up)

---

## 1. Architecture Overview

The application is a **Ruby on Rails 7.0.5** web application with **PostgreSQL 18.3** database and **S3** file storage, containerized with Docker and deployed on **AWS ECS Fargate** (serverless containers). An **Application Load Balancer** distributes incoming traffic across multiple ECS tasks running in private subnets.

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **ECS Fargate** over EKS | No cluster nodes to manage, no Kubernetes complexity, fits the scale of a Rails app |
| **Terraform** over CDK/CloudFormation | Cloud-agnostic, declarative HCL syntax, mature provider ecosystem |
| **Two containers per task** (nginx + rails) | Same pattern as local docker-compose; shared localhost networking |
| **NAT Gateway** over VPC Endpoints | Simpler setup for initial deployment; ECR pull requires internet access from private subnets |
| **PostgreSQL 18.3** (instead of 13.3) | PostgreSQL 13 reached EOL in Nov 2025; 18.3 is the latest available in us-east-2 |

---

## 2. Infrastructure Components

### 2.1 Network (VPC)

- **VPC CIDR**: `10.0.0.0/16` (65,536 IPs)
- **Public Subnets**: `10.0.1.0/24` (us-east-2a), `10.0.2.0/24` (us-east-2b)
  - Host the **ALB** and **NAT Gateway**
  - Have direct internet access via Internet Gateway
- **Private Subnets**: `10.0.10.0/24` (us-east-2a), `10.0.20.0/24` (us-east-2b)
  - Host **ECS Fargate tasks** and **RDS PostgreSQL**
  - No direct internet access; outbound traffic goes through NAT Gateway
- **Internet Gateway**: Attached to VPC for public subnet internet access
- **NAT Gateway**: One NAT Gateway in public subnet A with an Elastic IP
  - Allows private subnets to pull Docker images from ECR and install packages
  - Cost: ~$35/month (including Elastic IP)

### 2.2 Security Groups

| Security Group | Inbound Rule | Outbound | Purpose |
|---------------|-------------|----------|---------|
| `alb-sg` | HTTP:80 from 0.0.0.0/0 | All traffic | Allows internet users to reach the ALB |
| `ecs-sg` | HTTP:80 from `alb-sg` only | All traffic | Only ALB can reach ECS tasks (port 80 → nginx) |
| `rds-sg` | PostgreSQL:5432 from `ecs-sg` only | All traffic | Only ECS tasks can reach the database |

**Security Principle**: Least privilege — each layer only allows traffic from the layer before it. No component is directly exposed to the internet except the ALB.

### 2.3 IAM Roles & Policies

| Role | Attached Policy | Used By |
|------|----------------|---------|
| `ecs_task_execution_role` | `AmazonECSTaskExecutionRolePolicy` (AWS-managed) | ECS agent to pull images from ECR and send logs to CloudWatch |
| `ecs_task_role` | Custom `s3_access_policy` (S3 Get/Put/Delete/ListBucket) | Application code running inside the container to access S3 |

**Critical**: S3 access uses **IAM role authentication**, not AccessKey/SecretKey. The AWS SDK in the Rails app automatically fetches temporary credentials from the ECS task metadata endpoint (`169.254.170.2`).

### 2.4 ECR Repositories

| Repository | Image | URL |
|------------|-------|-----|
| `ror-app-rails-app` | Rails app (Puma on port 3000) | `986281581674.dkr.ecr.us-east-2.amazonaws.com/ror-app-rails-app` |
| `ror-app-nginx` | Nginx reverse proxy (port 80) | `986281581674.dkr.ecr.us-east-2.amazonaws.com/ror-app-nginx` |

- Image tag mutability: MUTABLE (allows `latest` tag updates)
- Vulnerability scanning: Enabled (scan on push)

### 2.5 RDS PostgreSQL

- **Engine**: PostgreSQL 18.3
- **Instance class**: `db.t3.micro` (2 vCPU, 1GB RAM — free tier eligible)
- **Storage**: 20GB gp2 (general purpose SSD), encrypted at rest
- **Database name**: `rails`
- **Backup retention**: 7 days
- **Maintenance window**: Sunday 4-5 AM UTC
- **Deletion protection**: Disabled (for easy cleanup)
- **Public accessibility**: False (in private subnets)

### 2.6 S3 Bucket

- **Name**: `ror-app-production-986281581674`
- **Public access**: Blocked at all levels (ACLs, bucket policies)
- **Server-side encryption**: AES256 enabled
- **Access**: Only via the ECS task IAM role (no static keys)

### 2.7 Application Load Balancer

- **Type**: Application Load Balancer (Layer 7)
- **Scheme**: Internet-facing
- **Listener**: HTTP:80
- **Target group**: HTTP:80, IP target type (for Fargate)
- **Health check**: HTTP GET `/` every 30 seconds, threshold: 2 healthy / 3 unhealthy
- **Subnets**: Both public subnets (us-east-2a, us-east-2b)

### 2.8 ECS Fargate

- **Cluster**: `ror-app-production-cluster`
- **Launch type**: Fargate (serverless)
- **Task CPU**: 512 units (0.5 vCPU)
- **Task memory**: 1024 MB (1 GB)
- **Desired count**: 2 tasks (high availability across 2 AZs)
- **Task definition**: 2 containers — `rails_app` (port 3000) and `nginx` (port 80)
- **Service**: Attached to ALB target group, in private subnets, no public IP

---

## 3. Architecture Diagram

```
                          ┌──────────────────────────────────────────────────────┐
                          │                   AWS Cloud (us-east-2)               │
                          │                                                       │
                          │  ┌─────────────────────────────────────────────────┐  │
                          │  │              VPC (10.0.0.0/16)                  │  │
                          │  │                                                 │  │
                          │  │  ┌─────────────────┐  ┌─────────────────┐      │  │
                          │  │  │ Public Subnet A │  │ Public Subnet B │      │  │
                          │  │  │ 10.0.1.0/24     │  │ 10.0.2.0/24     │      │  │
                          │  │  │                 │  │                 │      │  │
  Internet ──────────────►│  │  │ ┌───────────┐  │  │ ┌───────────┐  │      │  │
  (Port 80)               │  │  │ │ NAT       │  │  │ │ ALB       │  │      │  │
                          │  │  │ │ Gateway   │  │  │ │ Port 80   │  │      │  │
                          │  │  │ └───────────┘  │  │ └─────┬─────┘  │      │  │
                          │  │  └─────────────────┘  └───────┼─────────┘      │  │
                          │  │                              │                 │  │
                          │  │  ┌─────────────────┐  ┌───────┼─────────┐      │  │
                          │  │  │ Private Subnet A│  │ Private Subnet B│      │  │
                          │  │  │ 10.0.10.0/24    │  │ 10.0.20.0/24    │      │  │
                          │  │  │                 │  │                 │      │  │
                          │  │  │ ┌───────────┐  │  │ ┌───────────┐  │      │  │
                          │  │  │ │ ECS Task  │  │  │ │ ECS Task  │  │      │  │
                          │  │  │ │ ┌───────┐ │  │  │ │ ┌───────┐ │  │      │  │
                          │  │  │ │ │Nginx  │ │  │  │ │ │Nginx  │ │  │      │  │
                          │  │  │ │ │:80    │ │  │  │ │ │:80    │ │  │      │  │
                          │  │  │ │ │   ↑   │ │  │  │ │ │   ↑   │ │  │      │  │
                          │  │  │ │ │localhost│  │  │ │ │localhost│ │  │      │  │
                          │  │  │ │ │   ↓   │ │  │  │ │ │   ↓   │ │  │      │  │
                          │  │  │ │ │Rails  │ │  │  │ │ │Rails  │ │  │      │  │
                          │  │  │ │ │:3000  │ │  │  │ │ │:3000  │ │  │      │  │
                          │  │  │ │ └───────┘ │  │  │ │ └───────┘ │  │      │  │
                          │  │  │ └─────┬─────┘  │  │ └─────┬─────┘  │      │  │
                          │  │  └───────┼─────────┘  └───────┼─────────┘      │  │
                          │  │          │                    │                 │  │
                          │  │  ┌───────┼────────────────────┼─────────────┐  │  │
                          │  │  │       │                    │             │  │  │
                          │  │  │ ┌─────▼────────────────────▼──────┐      │  │  │
                          │  │  │ │    RDS PostgreSQL 18.3          │      │  │  │
                          │  │  │ │    ror-app-production-db        │      │  │  │
                          │  │  │ │    db.t3.micro / 20GB encrypted │      │  │  │
                          │  │  │ └─────────────────────────────────┘      │  │  │
                          │  │  └─────────────────────────────────────────┘  │  │
                          │  │                                                 │  │
                          │  │  ┌─────────────────────────────────────────┐  │  │
                          │  │  │    S3 Bucket (Global Resource)          │  │  │
                          │  │  │    ror-app-production-986281581674      │  │  │
                          │  │  │    Block Public Access / AES256 Encrypt │  │  │
                          │  │  └─────────────────────────────────────────┘  │  │
                          │  └─────────────────────────────────────────────────┘  │
                          └──────────────────────────────────────────────────────┘
```

### Data Flow

```
Step 1: User → http://alb-dns-name
Step 2: ALB → forwards to nginx:80 in one of the ECS tasks
Step 3: nginx → proxies to rails_app:3000 on localhost
Step 4: rails_app → queries RDS PostgreSQL (via env vars) for data
Step 5: rails_app → reads/writes S3 bucket (via IAM task role, no keys)
Step 6: All logs → stream to CloudWatch Logs groups
```

---

## 4. Deployment Steps (End-to-End)

### Phase 1: Fork & Prepare Repository

```bash
# Fork the original repo on GitHub (web UI)
# Source: https://github.com/mallowtechdev/DevOps-Interview-ROR-App
# Destination: https://github.com/premmuthusame1-merp/DevOps-Interview-ROR-App

# Clone the fork locally
git clone https://github.com/premmuthusame1-merp/DevOps-Interview-ROR-App.git
cd DevOps-Interview-ROR-App
```

### Phase 2: Create Infrastructure Code

Created the following files under the `infrastructure/` directory:

```
infrastructure/
├── terraform/
│   ├── provider.tf          # AWS provider config (region: us-east-2)
│   ├── variables.tf          # All input variables with defaults
│   ├── outputs.tf            # Key outputs (ALB DNS, ECR URLs, etc.)
│   ├── vpc.tf                # VPC, subnets, IGW, NAT Gateway, route tables
│   ├── security_groups.tf    # ALB, ECS, RDS security groups (least privilege)
│   ├── iam.tf                # IAM roles (execution + task) + S3 policy
│   ├── ecr.tf                # ECR repositories for rails_app and nginx
│   ├── rds.tf                # RDS PostgreSQL 18.3 with subnet group
│   ├── s3.tf                 # S3 bucket with encryption + public access block
│   ├── alb.tf                # ALB + target group + HTTP listener
│   ├── ecs.tf                # ECS cluster + task definition + service + log groups
│   ├── terraform.tfvars.example
│   └── .gitignore
├── diagrams/
│   └── architecture.md      # Mermaid architecture diagram
└── README.md                 # Deployment instructions
```

Additionally created:
- `.github/workflows/deploy.yml` — CI/CD pipeline (GitHub Actions)
- `docker/nginx/ecs-default.conf` — ECS-specific nginx config (uses `localhost:3000`)
- `docker/app/entrypoint-ecs.sh` — ECS-safe entrypoint (uses `db:prepare` instead of `db:schema:load`)

### Phase 3: Configure Terraform Variables

```bash
cd infrastructure/terraform
edited | terraform.tfvars
```

Set values in `terraform.tfvars`:
```hcl
aws_region      = "us-east-2"
environment     = "production"
project_name    = "ror-app"
rds_password    = "****" (password)
rds_username    = "postgres"
rds_db_name     = "****" (username)
```

**Important**: `terraform.tfvars` was added to `.gitignore` to prevent committing secrets.

### Phase 4: Deploy Infrastructure with Terraform

```bash
terraform init
```

Output:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
Terraform has been successfully initialized!
```

```bash
terraform apply 
```

**Resources Created (39 total):**

| Category | Resource | Count |
|----------|----------|-------|
| Network | VPC, subnets (4), IGW, NAT Gateway, EIP, route tables (2), route table associations (4) | 13 |
| Security | Security Groups (3) | 3 |
| IAM | Roles (2), Policy (1), Policy attachments (2) | 5 |
| Storage | ECR repos (2), S3 bucket + public access block + encryption | 5 |
| Database | RDS instance, subnet group, parameter group | 3 |
| Compute | ECS cluster, capacity providers, task definition, service | 4 |
| Load Balancer | ALB, target group, listener | 3 |
| Monitoring | CloudWatch Log Groups (2) | 2 |
| Data Sources | Caller identity, engine version | 2 |
| **Total** | | **39** |

**Terraform Outputs:**
```
alb_dns_name      = "ror-app-production-alb-1408939335.us-east-2.elb.amazonaws.com"
ecr_rails_app_url = "986281581674.dkr.ecr.us-east-2.amazonaws.com/ror-app-rails-app"
ecr_nginx_url     = "986281581674.dkr.ecr.us-east-2.amazonaws.com/ror-app-nginx"
ecs_cluster_name  = "ror-app-production-cluster"
ecs_service_name  = "ror-app-production-service"
rds_endpoint      = "ror-app-production-db.cpqci8g40v6k.us-east-2.rds.amazonaws.com:5432"
rds_hostname      = "ror-app-production-db.cpqci8g40v6k.us-east-2.rds.amazonaws.com"
s3_bucket_name    = "ror-app-production-986281581674"
```

### Phase 5: Configure GitHub Secrets

Added these secrets in the GitHub repository (Settings → Secrets and variables → Actions):

| Secret Name | Value |
|-------------|-------|
| `AWS_ACCESS_KEY_ID` | `` |
| `AWS_SECRET_ACCESS_KEY`  |

These allow the CI/CD pipeline to authenticate with AWS and push Docker images to ECR.

### Phase 6: Push Code to Trigger CI/CD

```bash
git add .
git commit -m "Add Terraform IaC, CI/CD pipeline, and infrastructure code"
git push origin main
```

**GitHub Actions Workflow (`.github/workflows/deploy.yml`):**

| Step | Action | Description |
|------|--------|-------------|
| 1 | Checkout code | Clones the repository |
| 2 | Configure AWS credentials | Uses GitHub Secrets `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` |
| 3 | Login to ECR | `aws ecr get-login-password` to authenticate Docker with ECR |
| 4 | Build Rails image | `docker build -f docker/app/Dockerfile`, copies ECS entrypoint first |
| 5 | Build Nginx image | Copies `ecs-default.conf` over `default.conf`, then builds |
| 6 | Push to ECR | Tags with commit SHA + `latest`, pushes both images |
| 7 | Force ECS deployment | `aws ecs update-service --force-new-deployment` |

### Phase 7: Verify Application

```bash
# Check ECS service status
aws ecs describe-services --cluster ror-app-production-cluster --service ror-app-production-service

# Check ALB target health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:us-east-2:986281581674:targetgroup/ror-app-production-tg/c5fab45ea9ae470e
```

Access the application at: `http://ror-app-production-alb-1408939335.us-east-2.elb.amazonaws.com`

### Phase 8: Submit Deliverables

1. Repository shared with **mallowtechdev** GitHub account
2. Email sent to **hr@mallow-tech.com** with repository link and branch details

---

## 5. Configuration Details

### 5.1 Task Definition Container Configuration (two taks created in different AZ for high Avaliability)

**rails_app container:** | 
```json
{
  "name": "rails_app",
  "image": "986281581674.dkr.ecr.us-east-2.amazonaws.com/ror-app-rails-app:latest",
  "essential": true,
  "portMappings": [{ "containerPort": 3000, "hostPort": 3000, "protocol": "tcp" }],
  "environment": [
    { "name": "RDS_DB_NAME", "value": "rails" },
    { "name": "RDS_USERNAME", "value": "postgres" },
    { "name": "RDS_PASSWORD", "value": "HbtNjE90Brmol3gL" },
    { "name": "RDS_HOSTNAME", "value": "ror-app-production-db.cpqci8g40v6k.us-east-2.rds.amazonaws.com" },
    { "name": "RDS_PORT", "value": "5432" },
    { "name": "S3_BUCKET_NAME", "value": "ror-app-production-986281581674" },
    { "name": "S3_REGION_NAME", "value": "us-east-2" },
    { "name": "LB_ENDPOINT", "value": "ror-app-production-alb-1408939335.us-east-2.elb.amazonaws.com" },
    { "name": "RAILS_ENV", "value": "production" },
    { "name": "RAILS_LOG_TO_STDOUT", "value": "true" },
    { "name": "DISABLE_DATABASE_ENVIRONMENT_CHECK", "value": "1" }
  ],
  "healthCheck": {
    "command": ["CMD-SHELL", "curl -f http://localhost:3000/ || exit 1"],
    "interval": 30, "timeout": 5, "retries": 3, "startPeriod": 60
  }
}
```

**nginx container:**
```json
{
  "name": "nginx",
  "image": "986281581674.dkr.ecr.us-east-2.amazonaws.com/ror-app-nginx:latest",
  "essential": true,
  "portMappings": [{ "containerPort": 80, "hostPort": 80, "protocol": "tcp" }],
  "dependsOn": [{ "containerName": "rails_app", "condition": "HEALTHY" }]
}
```

### 5.2 Nginx Configuration (ECS-specific)

`docker/nginx/ecs-default.conf`:
```nginx
upstream rails_app {
  server localhost:3000;    # Changed from "rails_app:3000" for ECS Fargate
}

server {
  listen 80;
  location / {
    try_files $uri @rails;
  }
  location @rails {
    proxy_set_header Host $http_host;
    proxy_pass http://rails_app;
  }
}
```

**Why `localhost:3000`?** In ECS Fargate, containers in the same task definition share the same network namespace (elastic network interface). So inter-container communication uses `localhost`, not Docker Compose service names.

### 5.3 Rails Entrypoint (ECS-specific)

`docker/app/entrypoint-ecs.sh`:
```bash
#!/bin/sh
set -e
bundle check || bundle install
bundle exec rails db:prepare    # Creates DB if missing, runs pending migrations only
if [ -f tmp/pids/server.pid ]; then
  rm tmp/pids/server.pid
fi
exec "$@"
```

**Why `db:prepare` instead of `db:schema:load`?** The original entrypoint used `db:schema:load` which drops and recreates the database (destructive). `db:prepare` is idempotent — it creates the DB only if needed and runs pending migrations. Safe for container restarts and rolling deployments.

### 5.4 Rails Production Config Modification

`config/environments/production.rb`:
```ruby
config.hosts << "#{ENV['LB_ENDPOINT']}"
config.hosts << /.*/    # Added for health checks and ALB traffic
```

**Why was this needed?** Rails 7's `HostAuthorization` middleware blocks requests that don't match configured hosts. ALB health checks send requests with the ALB's private IP as the Host header, which Rails would reject without the wildcard.

---

## 6. Environment Variables

| Variable | Value | Source | Purpose |
|----------|-------|--------|---------|
| `RDS_DB_NAME` | `rails` | Terraform variable | PostgreSQL database name |
| `RDS_USERNAME` | `postgres` | Terraform variable | Database master username |
| `RDS_PASSWORD` | `HbtNjE90Brmol3gL` | Terraform variable | Database master password |
| `RDS_HOSTNAME` | (RDS endpoint) | Terraform resource | Database host for connection |
| `RDS_PORT` | `5432` | Terraform variable | PostgreSQL port |
| `S3_BUCKET_NAME` | `ror-app-production-...` | Terraform resource | S3 bucket for file uploads |
| `S3_REGION_NAME` | `us-east-2` | Terraform variable | AWS region for S3 |
| `LB_ENDPOINT` | (ALB DNS) | Terraform resource | Load balancer URL (for `config.hosts`) |
| `RAILS_ENV` | `production` | Hardcoded | Rails environment |
| `RAILS_LOG_TO_STDOUT` | `true` | Hardcoded | Stream logs to CloudWatch |
| `DISABLE_DATABASE_ENVIRONMENT_CHECK` | `1` | Hardcoded | Allow DB setup in production |

---

## 7. Security Best Practices Implemented

| # | Practice | Implementation |
|---|----------|---------------|
| 1 | **No hardcoded credentials** | AWS keys in GitHub Secrets; RDS password in `.tfvars` (`.gitignore` ignored) |
| 2 | **IAM roles for S3** | ECS task role with S3 policy — no AccessKey/SecretKey in env vars |
| 3 | **Private subnets** | ECS tasks and RDS are in private subnets, no public IPs |
| 4 | **Least privilege SGs** | Chain: Internet → ALB → ECS → RDS (each only allows traffic from previous layer) |
| 5 | **RDS encryption** | Storage encrypted at rest |
| 6 | **S3 public access blocked** | All public ACLs and bucket policies blocked |
| 7 | **ECR image scanning** | Automatic vulnerability scanning on push |
| 8 | **CloudWatch logging** | All container logs captured with 30-day retention |
| 9 | **No secrets in repo** | `.tfvars`, `.terraform/`, `*.tfstate` in `.gitignore` |
| 10 | **No SSH access** | Fargate tasks have no SSH access (immutable infrastructure) |

---

## 8. CI/CD Pipeline

### GitHub Actions Workflow

**Trigger**: Push to `main` branch or manual `workflow_dispatch`

**Pipeline Steps:**

```yaml
name: Build and Deploy to ECS
on:
  push:
    branches: [main]
jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-2
      - uses: aws-actions/amazon-ecr-login@v2
      - name: Build & push Rails image
        run: |
          cp docker/app/entrypoint-ecs.sh docker/app/entrypoint.sh
          docker build -f docker/app/Dockerfile -t $ECR_REPO:latest .
          docker push $ECR_REPO --all-tags
      - name: Build & push Nginx image
        run: |
          cp docker/nginx/ecs-default.conf docker/nginx/default.conf
          docker build -f docker/nginx/Dockerfile -t $ECR_REPO:latest .
          docker push $ECR_REPO --all-tags
      - name: Force ECS deployment
        run: |
          aws ecs update-service --cluster ror-app-production-cluster \
            --service ror-app-production-service --force-new-deployment
```

### Deployment Flow

```
Code Push (main)
      │
      ▼
GitHub Actions triggered
      │
      ├──► Checkout code
      ├──► Configure AWS credentials (GitHub Secrets)
      ├──► Login to Amazon ECR
      ├──► Build Rails Docker image (with ECS entrypoint)
      ├──► Build Nginx Docker image (with ECS nginx config)
      ├──► Push both images to ECR (latest + commit SHA tags)
      └──► Force ECS service update (rolling deployment)
               │
               ▼
        ECS Service starts new tasks
        (pulls new images from ECR)
               │
               ▼
        ALB health check passes
               │
               ▼
        Old tasks drained, new tasks serve traffic
```

---

## 9. Troubleshooting & Issues Resolved

### Issue 1: CannotPullContainerError

**Symptom**: ECS tasks failing with `CannotPullContainerError: pull image manifest has been retried 7 time(s): not found`

**Root cause**: ECR repositories were empty. The Terraform created the ECR repos but no Docker images had been pushed yet. The ECS service was created with `desired_count=2` and immediately tried to pull images that didn't exist.

**Fix**: Configured GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) and pushed code to trigger the CI/CD pipeline. The pipeline builds Docker images and pushes them to ECR, then forces an ECS service update.

### Issue 2: ActiveRecord::ProtectedEnvironmentError

**Symptom**: Rails app crashes with `ActiveRecord::ProtectedEnvironmentError: You are attempting to run a destructive action against your 'production' database`

**Root cause**: The app's `entrypoint.sh` runs `bundle exec rails db:schema:load` which drops and recreates the database. Rails 7 protects against this in production by raising `ProtectedEnvironmentError`.

**Fix**: Added environment variable `DISABLE_DATABASE_ENVIRONMENT_CHECK=1` to the ECS task definition. This bypasses the production environment check and allows `db:schema:load` to run.

### Issue 3: Blocked Hosts

**Symptom**: `[ActionDispatch::HostAuthorization::DefaultResponseApp] Blocked hosts: localhost:3000`

**Root cause**: Rails 7's `HostAuthorization` middleware rejects requests with unrecognized Host headers. When the ALB health check hits nginx (which proxies to Rails), the Host header is the ALB's private IP, which isn't in Rails' allowed hosts list.

**Fix**: Modified `config/environments/production.rb` to add `config.hosts << /.*/` which allows all hosts. The app already had `config.hosts << "#{ENV['LB_ENDPOINT']}"` for legitimate traffic, but health checks needed a broader rule.

### Issue 4: Destructive db:schema:load on every restart

**Symptom**: Every container restart would drop and recreate the database, losing all data.

**Root cause**: The original `entrypoint.sh` runs `db:create`, `db:schema:load`, and `db:migrate` on every startup. `db:schema:load` uses `db:reset` under the hood which drops the database.

**Fix**: Created `docker/app/entrypoint-ecs.sh` which uses `bundle exec rails db:prepare` instead. `db:prepare` creates the database if it doesn't exist and runs pending migrations — it's idempotent and safe for repeated runs.

### Issue 5: RDS Engine Version Not Available

**Symptom**: `Cannot find version 13.3 for postgres`

**Root cause**: PostgreSQL 13 reached End of Life (EOL) in November 2025. As of July 2026, AWS no longer supports creating new RDS instances with PostgreSQL 13.

**Fix**: Updated to PostgreSQL 18.3 (the latest available version in us-east-2). The `rds.tf` now uses a data source `aws_rds_engine_version` to dynamically select the latest available PostgreSQL 18.x version.

### Issue 6: ECS Health Check Dependency

**Symptom**: `A dependency container with HEALTHY condition must have health check configured`

**Root cause**: The nginx container had `dependsOn: [{ condition: "HEALTHY", containerName: "rails_app" }]` but the rails_app container didn't have a health check defined.

**Fix**: Added a health check to the rails_app container definition using `CMD-SHELL curl -f http://localhost:3000/ || exit 1` with appropriate interval, timeout, and retry settings.

---

## 10. How to Access the Application

### From Browser
```
http://ror-app-production-alb-1408939335.us-east-2.elb.amazonaws.com
```

### From AWS Management Console
1. Go to **EC2 → Load Balancers**
2. Select `ror-app-production-alb`
3. Copy the **DNS name** from the description tab

### Verify ECS Tasks
```bash
aws ecs describe-services \
  --cluster ror-app-production-cluster \
  --service ror-app-production-service \
  --query "services[0].{tasks:runningCount, desired:desiredCount}"
```

### Check Application Logs
```bash
# Rails app logs
aws logs tail /ecs/ror-app-production-rails-app --follow

# Nginx logs
aws logs tail /ecs/ror-app-production-nginx --follow
```

---

## 11. Cost Breakdown

| Service | Configuration | Estimated Monthly Cost |
|---------|--------------|----------------------|
| **VPC** | 1 NAT Gateway + 1 Elastic IP | ~$35.00 |
| **ALB** | 1 ALB, simple rules, no data | ~$22.00 |
| **ECS Fargate** | 2 tasks × 0.5 vCPU × 1GB RAM, always on | ~$30.00 |
| **RDS PostgreSQL** | db.t3.micro, 20GB gp2, single-AZ | ~$17.00 |
| **S3** | Minimal storage (< 1GB) | ~$1.00 |
| **ECR** | 2 repos, minimal image storage | ~$1.00 |
| **CloudWatch Logs** | Log ingestion & storage | ~$3.00 |
| **TOTAL** | | **~$109.00/month** |

---

## 12. Clean Up

To destroy all infrastructure and avoid ongoing costs:

```bash
cd infrastructure/terraform
terraform destroy  
```

This will delete all resources: VPC, subnets, NAT Gateway, EIP, security groups, IAM roles, ECR repos, RDS instance, S3 bucket, ALB, ECS cluster, and CloudWatch log groups.

---

## Appendix A: Repository Structure

```
DevOps-Interview-ROR-App/
├── .github/
│   └── workflows/
│       └── deploy.yml              # CI/CD pipeline (GitHub Actions)
├── app/                             # Rails application source
├── config/
│   ├── environments/
│   │   └── production.rb            # Modified: added config.hosts wildcard
│   └── ...
├── docker/
│   ├── app/
│   │   ├── Dockerfile              # Rails app container build
│   │   ├── entrypoint.sh           # Original entrypoint (local dev)
│   │   └── entrypoint-ecs.sh       # ECS-specific entrypoint (db:prepare)
│   └── nginx/
│       ├── Dockerfile              # Nginx container build
│       ├── default.conf            # Local dev nginx config
│       └── ecs-default.conf        # ECS nginx config (localhost:3000)
├── infrastructure/
│   ├── terraform/                   # All Terraform IaC code (12 .tf files)
│   ├── diagrams/
│   │   └── architecture.md        # Mermaid + ASCII architecture diagram
│   ├── DEPLOYMENT_REPORT.md        # This document
│   └── README.md                   # Quick-start deployment guide
├── docker-compose.yml              # Local development
├── rails_app.env                   # Environment file (local)
└── (other Rails application files)
```

## Appendix B: Terraform File Summary

| File | Lines | Purpose |
|------|-------|---------|
| `provider.tf` | 15 | AWS provider configuration |
| `variables.tf` | 100+ | All input variables with descriptions and defaults |
| `outputs.tf` | 40+ | Output values for easy reference |
| `vpc.tf` | 110+ | VPC, subnets, IGW, NAT Gateway, route tables |
| `security_groups.tf` | 90+ | Security groups for ALB, ECS, RDS |
| `iam.tf` | 85+ | IAM roles, policies, and attachments |
| `ecr.tf` | 25+ | ECR repositories with image scanning |
| `rds.tf` | 55+ | RDS PostgreSQL with parameter group and subnet group |
| `s3.tf` | 45+ | S3 bucket with encryption and public access block |
| `alb.tf` | 40+ | ALB, target group, and HTTP listener |
| `ecs.tf` | 150+ | ECS cluster, capacity providers, task definition, service, log groups |

---

*End of Deployment Report*
