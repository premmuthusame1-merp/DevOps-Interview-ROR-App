Application Deployment Report

Prepared by:
premmuthusame
Date:
July 20, 2026
Repository:
https://github.com/premmuthusame1-merp/DevOps-Interview-ROR-App
Infrastructure Code:
Terraform (us-east-2)


1. Architecture Overview
The deployed infrastructure runs a containerized Ruby on Rails 7.0.5 application connected to a PostgreSQL 18.3 database and Amazon S3 for file storage. The compute layer utilizes AWS ECS Fargate, providing a serverless container environment that scales without the need to manage underlying EC2 instances. Public-facing Ib traffic is routed through an Application Load Balancer (ALB), which balances the load across Fargate tasks distributed across private subnets for high availability.


FYI  : PostgreSQL 13 reached End of Life (EOL) in November 2025
Key Design Decisions & Rationale
Decision
Rationale
AWS ECS Fargate
Here I working on simple application so i have used ECS over EKS.
Terraform for IaC
For managing and Provision infra i have used Terraform as IAC
Dual Containers per Task
Runs Nginx and Rails within the same task definition, mirroring local development configurations through shared localhost networking on port 3000.
NAT Gateway Integration
Placed a NAT Gateway in the public subnet to allow Fargate tasks in private subnets to pull images from ECR and fetch packages from the internet during runtime.
PostgreSQL 18.3 Engine
PostgreSQL 13 reached End of Life (EOL) in November 2025. Version 18.3 was selected as the latest stable version supported in the us-east-2 region.

2. Infrastructure Components
2.1 VPC and Networking
The network architecture is built within a dedicated VPC using the 10.0.0.0/16 CIDR block. To ensure high availability, the infrastructure is distributed across two Availability Zones (AZs) in us-east-2:
Public Subnets: 10.0.1.0/24 (us-east-2a) and 10.0.2.0/24 (us-east-2b) host the Application Load Balancer and the NAT Gateway. These subnets are attached directly to the Internet Gateway.
Private Subnets: 10.0.10.0/24 (us-east-2a) and 10.0.20.0/24 (us-east-2b) host the ECS Fargate tasks and the RDS PostgreSQL instance. Outbound internet traffic goes through the NAT Gateway.
Internet Gateway: Attached to the VPC to enable internet access for public subnets.
NAT Gateway: A single NAT Gateway is deployed in public subnet A and associated with an Elastic IP. This allows resmyces in the private subnets to pull container images from ECR and execute dependencies installer scripts.
2.2 Security Groups
To implement the principle of least privilege, access betIen different components is locked down at the network level:
Security Group
Inbound Rule
Outbound Rule


alb-sg
HTTP (port 80) from 0.0.0.0/0
All Traffic (0.0.0.0/0)
Allows user HTTP traffic to reach the ALB.
ecs-sg
HTTP (port 80) from alb-sg only
All Traffic (0.0.0.0/0)
Restricts task access so that only the ALB can route traffic to Nginx on port 80.
rds-sg
PostgreSQL (port 5432) from ecs-sg only
All Traffic (0.0.0.0/0)
Secures database access so that only ECS Fargate tasks can query the PostgreSQL instance.

2.3 IAM Roles & Custom Policies
I configured two distinct IAM roles to control container execution and resmyce access:
ecs_task_execution_role: Uses the AWS-managed AmazonECSTaskExecutionRolePolicy. This allows the ECS container agent to authenticate with ECR, pull the application images, and write logs to CloudWatch.
ecs_task_role: Assigned to the running Rails application container. It uses a custom policy that allows GetObject, PutObject, DeleteObject, and ListBucket actions on S3. 
2.4 Amazon ECR Repositories
Two container repositories Ire created in Elastic Container Registry (ECR). Both repositories are mutable to allow tag overwrites and vulnerability scanning is enabled.
2.5 RDS PostgreSQL Database
I deployed a secure, managed database instance inside my private subnets:
Engine: PostgreSQL 18.3 (PostgreSQL 13 reached EOL)
Instance Class: db.t3.micro (2 vCPUs, 1GB RAM) — I have used free tier.
Storage: 20GB gp2 (General Purpose SSD), encrypted at rest.
I keep Database Name as rails 
Backup Strategy: 7-day automated backup retention.
Configuration: Public accessibility is set to False, and deletion protection is disabled for testing convenience.
2.6 Amazon S3 Storage
An S3 bucket is provisioned for application asset uploads and data storage:
Bucket Name: ror-app-production
Encryption: AES256 server-side encryption enabled.
Security: All public access block settings are enabled. Only via ECS task role not using static keys
2.7 Application Load Balancer
Listener: Port 80 (HTTP).
Target Group has configured.
Health Check: Sends HTTP GET requests to '/' every 30 seconds. Healthy threshold is set to 2, and unhealthy threshold is set to 3.
Subnet: public subnets in both Availability Zones (us-east-2a and us-east-2b).
2.8 ECS Fargate Cluster & Service
The application runs on ECS Fargate tasks:
I have given Cluster Name as  ror-app-production-cluster
Compute Allocation as 512 CPU units (0.5 vCPU) and 1024 MB (1 GB) memory per task.
Scaling Desired count is set to 2 tasks for high availability across the private subnets.
Container Setup for Nginx (port 80) and rails_app (port 3000) run together in a single task definition.
Security: The service runs in private subnets with no public IPs assigned, relying on the ALB for incoming traffic.
3. System Architecture Diagram
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
                          │  │  │    S3 Bucket (Global Resmyce)          │  │  │
                          │  │  │    ror-app-production-986281581674      │  │  │
                          │  │  │    Block Public Access / AES256 Encrypt │  │  │
                          │  │  └─────────────────────────────────────────┘  │  │
                          │  └─────────────────────────────────────────────────┘  │
                          └──────────────────────────────────────────────────────┘


Data Flow Architecture
Step 1: The user accesses the application by navigating to the ALB DNS name (HTTP port 80).
Step 2: The ALB forwards the incoming request to the Nginx container (port 80) inside one of the Fargate tasks.
Step 3: Nginx acts as a reverse proxy and passes the request to the Rails container ( running on port 3000) over localhost networking.
Step 4: The Rails app connects to the PostgreSQL database (RDS) to fetch or persist data.
Step 5: Active storage uploads or asset accesses are handled directly through the S3 bucket using IAM role temporary credentials.
Step 6: Standard out and standard error logs from both Nginx and Rails application will pushed directly to Amazon CloudWatch.
4. End-to-End Deployment Workflow
Phase 1: Forking & Cloning the Repository
I forked the original repository from 'mallowtechdev' on GitHub to create my working repository at https://github.com/premmuthusame1-merp/DevOps-Interview-ROR-App. Next, I cloned it to my local environment:
git clone https://github.com/premmuthusame1-merp/DevOps-Interview-ROR-App.git
cd DevOps-Interview-ROR-App

Phase 2: Creating Infrastructure-as-Code Files
I wrote and structured my Terraform codebase in a new 'infrastructure/' folder:
provider.tf: Configures the AWS provider targeting the us-east-2 region.
variables.tf: Declares customizable variables with safe defaults.
outputs.tf: Exposes endpoints (ALB DNS, ECR URLs, RDS host, S3 bucket name) for other pipelines and commands.
vpc.tf: Configures the VPC, public/private subnets, IGW, NAT Gateway, EIP, and route tables.
security_groups.tf: Defines strict traffic rules for the ALB, containers, and RDS.
iam.tf: Sets up execution and task roles, along with the custom S3 policy.
ecr.tf: Provisions the ECR repositories with scanning on push enabled.
rds.tf: Creates the PostgreSQL 18.3 database and its subnet configuration.
s3.tf: Sets up the secure S3 storage bucket and blocks all public access.
alb.tf: Builds the ALB, listener, and target group.
ecs.tf: Sets up the Fargate cluster, task definitions (including both containers), Fargate service, and CloudWatch log groups.
I also created the configuration files:
.github/workflows/deploy.yml: Configures the GitHub Actions CI/CD pipeline.
docker/nginx/ecs-default.conf: Configures Nginx to route traffic to localhost:3000 inside the Fargate task.
docker/app/entrypoint-ecs.sh: Contains the startup script using db:prepare to safely initialize the database instead of db:schema:load because it make create new DB each time when container updates
Phase 3: Configuring Local Variables
I created a 'terraform.tfvars' file within the 'infrastructure/terraform/' directory to declare local deployment settings:
aws_region      = "us-east-2"
environment     = "production"
project_name    = "ror-app"
rds_password    = "****" (I have set on my own while working)
rds_username    = "postgres"
rds_db_name     = "****" (I have set on my own while working)

Note: The 'terraform.tfvars' file was added to '.gitignore' to prevent credentials from being committed to the repository while pushing to Git.
Phase 4: Running Terraform to Deploy 
I initialized the directory to download the AWS provider plugins (v5.100.0):
terraform init

I then deployed the infrastructure:
terraform apply

This execution successfully provisioned including the VPC, security groups, IAM execution/task roles, ECR repositories, S3 bucket, RDS instance, ALB, and the ECS Fargate cluster/service. 
Phase 5: Configuring GitHub Repository Secrets
In the GitHub repository settings, I configured two actions secrets to authorize my deployment workflow:
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
Phase 6: Triggering the CI/CD Pipeline
I committed and pushed my files to the main branch to start the build pipeline:
git add .
git commit -m "Add Terraform IaC, CI/CD pipeline, and infrastructure code"
git push origin main

This triggered my GitHub Actions workflow, which built both the Rails and Nginx Docker images (incorporating the ECS-specific configuration files), pushed them to the ECR repositories under the 'latest', and triggered a rolling deployment on my ECS service.
Phase 7: Verifying the Application Status
Once the pipeline completed, I checked the status of my Fargate tasks and load balancer target group health:
What i have runned in shell to check the status
aws ecs describe-services --cluster ror-app-production-cluster --service ror-app-production-service
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:us-east-2:986281581674:targetgroup/ror-app-production-tg/c5fab45ea9ae470e

The application was confirmed running and accessible publicly at the ALB endpoint: http://ror-app-production-alb-1408939335.us-east-2.elb.amazonaws.com
5. Configuration Details
5.1 ECS Container Definitions
The ECS Task Definition contains two container definitions running within the Fargate task:
Rails App Container
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
    "interval": 30,
    "timeout": 5,
    "retries": 3,
    "startPeriod": 60
  }
}

Nginx Container
{
  "name": "nginx",
  "image": "986281581674.dkr.ecr.us-east-2.amazonaws.com/ror-app-nginx:latest",
  "essential": true,
  "portMappings": [{ "containerPort": 80, "hostPort": 80, "protocol": "tcp" }],
  "dependsOn": [{ "containerName": "rails_app", "condition": "HEALTHY" }]
}

5.2 Nginx Configuration (docker/nginx/ecs-default.conf)
Since the containers share localhost networking within the Fargate task, Nginx is configured to pass requests to the Rails app on localhost:3000 rather than using container hostname routing:
upstream rails_app {
  server localhost:3000;
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

5.3 Rails Entrypoint (docker/app/entrypoint-ecs.sh)
I modified the docker entrypoint script to run 'rails db:prepare' instead of 'db:schema:load'. This is an important adjustment for Fargate: 'db:prepare' is idempotent, meaning it will create the database if it does not exist and run pending migrations without wiping existing data. This makes it safe to run during task restarts or rolling updates:
#!/bin/sh
set -e
bundle check || bundle install
bundle exec rails db:prepare
if [ -f tmp/pids/server.pid ]; then
  rm tmp/pids/server.pid
fi
exec "$@"

5.4 Rails Production Config (config/environments/production.rb)
To allow requests originating from the ALB and the ALB health check, I updated the Rails production host configuration:
config.hosts << "#{ENV['LB_ENDPOINT']}"
config.hosts << /.*/

Adding the wildcard matcher prevents Rails from raising HostAuthorization errors when the ALB health checks the tasks using their private IP addresses.
6. Environment Variables
The following environment variables are supplied to the Rails container in the task definition:
Variable
Value




RDS_DB_NAME
rails
Terraform variable
Specifies the PostgreSQL database name.
RDS_USERNAME
****
Terraform variable
Specifies the database administrator username.
RDS_PASSWORD
****
Terraform variable
Specifies the database password.
RDS_HOSTNAME
ror-app-production-db.cpqci8g40v6k...
Terraform resource
Defines the endpoint address of the RDS database.
RDS_PORT
5432
Terraform variable
Specifies the PostgreSQL port.
S3_BUCKET_NAME
ror-app-production-986281581674
Terraform resource
Name of the S3 bucket for uploads.
S3_REGION_NAME
us-east-2
Terraform variable
AWS region hosting the S3 bucket.
LB_ENDPOINT
ror-app-production-alb-1408939335...
Terraform resource
The DNS name of the ALB, used for Rails host verification.
RAILS_ENV
production
Hardcoded
Forces Rails to run in production mode.
RAILS_LOG_TO_STDOUT
true
Hardcoded
Streams application logs directly to stdout for CloudWatch ingestion.
DISABLE_DATABASE_ENVIRONMENT_CHECK
1
Hardcoded
Bypasses safety checks to allow database migrations in production.


7. Security wise Implementation
Security was configured across the infrastructure to comply with industry standards:
No Plaintext Credentials: Local secrets are isolated in terraform.tfvars, which is git-ignored. Codebase AWS keys are stored in encrypted GitHub Secrets.
Role-Based AWS Permissions: The Rails app connects to S3 using an IAM task role instead of hardcoding static credentials in the environment variables.
Private Subnet Isolation: Compute tasks and the RDS instance are running in private subnets, meaning they do not possess public IP addresses and cannot be reached directly from the internet.
Layered Security Groups: Inbound rules are restricted so that only the ALB can access the ECS tasks, and only the ECS tasks can access the RDS database.
Data Encryption: The RDS instance's storage volume is encrypted at rest using KMS, and the S3 bucket enforces AES256 server-side encryption.
S3 Public Access Blocked: The S3 bucket blocks all public access
ECR Vulnerability Scanning: ECR is configured to scan Docker images on push to locate security vulnerabilities.
Centralized Logging: Logs from all containers are automatically sent to CloudWatch Logs with a 30-day retention period.
Immutable Deployments: Fargate container tasks have SSH disabled. Updates are applied only by deploying new images.
8. CI/CD Pipeline
my GitHub Actions workflow is triggered on pushes to the 'main' branch or manually via 'workflow_dispatch'. The workflow steps are structured as follows:
Step
Action
Description
1
Checkout Code
Retrieves the repository files.
2
Configure AWS Credentials
Authenticates to AWS using GitHub repository secrets.
3
Log in to Amazon ECR
Authenticates the local runner's Docker client with the ECR registry.
4
Build & Push Rails Image
Copies the ECS entrypoint script over the dev entrypoint, builds the Rails image, tags it, and pushes it to ECR.
5
Build & Push Nginx Image
Copies the ECS Nginx configuration, builds the Nginx image, tags it, and pushes it to ECR.
6
Force ECS Deployment
Runs 'aws ecs update-service' with the force redeployment flag to update the Fargate tasks with the new images.


Deployment Architecture Flow
Code Push to main branch
      │
      ▼
GitHub Actions Pipeline Triggered
      ├──► Clones repository files
      ├──► Authenticates with AWS using Secrets
      ├──► Logs into ECR Registry
      ├──► Builds & Pushes Rails Container (with entrypoint-ecs.sh)
      ├──► Builds & Pushes Nginx Container (with ecs-default.conf)
      └──► Forces ECS Service rolling update
               │
               ▼
        ECS service spins up new Fargate tasks
        (pulls latest container images)
               │
               ▼
        ALB target group health checks pass
               │
               ▼
        Old tasks are drained and replaced


9. Issue faced and Troubleshooting 
During deployment, I resolved several configuration challenges:
Issue 1: Container Pull Error (CannotPullContainerError)
Symptom: The ECS tasks failed to start, returning a pull manifest retry timeout error.
Root Cause: The ECS service was created before the build pipeline had pushed container images to the ECR repositories, leaving the repositories empty.
Resolution: I configured the AWS secrets in the repository and pushed the codebase to trigger the CI/CD pipeline, building and pushing the images before ECS pulled them.
Issue 2: ActiveRecord Protected Environment Error
Symptom: The Rails application crashed during start, throwing a ProtectedEnvironmentError.
Root Cause: The original entrypoint script ran 'rails db:schema:load', which drops the database. Rails protects against destructive commands in production.
Resolution: I added the DISABLE_DATABASE_ENVIRONMENT_CHECK=1 environment variable to the task definition to disable this protection.
Issue 3: Blocked Host Request Errors
Symptom: Connections through the load balancer failed with a Blocked Hosts warning.
Root Cause: Rails' HostAuthorization middleware rejected connections because the ALB health checks hit the tasks using private IPs rather than the configured domain name.
Resolution: I added config.hosts << /.*/ to config/environments/production.rb, allowing Rails to accept requests routed to any IP address.
Issue 4: Destructive Startup Database Setup
Symptom: Every container restart caused database data loss.
Root Cause: The default entrypoint executed db:schema:load on startup, which dropped and rebuilt the database tables on every launch.
Resolution: I created docker/app/entrypoint-ecs.sh, which uses rails db:prepare instead of db:schema:load. This safely migrates the database only if migrations are pending, protecting data across task restarts.
Issue 5: Missing PostgreSQL Version on RDS
Symptom: Terraform failed, stating PostgreSQL version 13.3 was not available.
Root Cause: PostgreSQL 13.3 reached EOL in November 2025, and AWS has disabled provisioning of new instances on that version.
Resolution: I updated the database version to PostgreSQL 18.3 in rds.tf, 

Issue 6: Task Definition Dependency Health Checks
Symptom: The Fargate task definition failed registration.
Root Cause: The Nginx container definition declared a startup dependency on the rails_app container being 'HEALTHY', but rails_app did not have a health check block configured.
Resolution: I added a health check definition to the rails_app container block in ecs.tf using a curl command against http://localhost:3000.
10. Verifying & Accessing the Application
Public Access
The application is publicly accessible at the load balancer endpoint:
http://ror-app-production-alb-1408939335.us-east-2.elb.amazonaws.com



Task Status Check

Accessing Logs on cloud trail

12. Resource Cleanup
I have destroy all deployed resources and prevent ongoing AWS charges, 
cd infrastructure/terraform
terraform destroy


