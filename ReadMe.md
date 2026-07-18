# DevOps Interview ROR App - Infrastructure Deployment

This repository contains the complete Infrastructure as Code (IaC) solution for deploying the Ruby on Rails web application on AWS using ECS Fargate, Terraform, and GitHub Actions.

## Repository Structure

```
├── .github/workflows/deploy.yml   # CI/CD pipeline (GitHub Actions)
├── docker/                         # Docker configuration
│   ├── app/Dockerfile             # Rails app container
│   ├── nginx/
│   │   ├── Dockerfile             # Nginx container
│   │   ├── default.conf           # Local development config
│   │   └── ecs-default.conf       # ECS-specific config (localhost)
│   └── docker-compose.yml         # Local development
├── infrastructure/                 # IaC and documentation
│   ├── terraform/                 # Terraform scripts
│   └── README.md                  # Deployment instructions
└── (Rails application source)
```

## Quick Start

1. **Deploy infrastructure**:
   ```bash
   cd infrastructure/terraform
   terraform init
   terraform apply
   ```

2. **Push code to trigger build**:
   ```bash
   git push origin main
   ```

3. **Access application** at the ALB DNS URL from Terraform output.

## Key Features

- **ECS Fargate** — Serverless container orchestration
- **ALB** — Traffic distribution across tasks
- **RDS PostgreSQL** — Managed database
- **S3** — Object storage with IAM role authentication
- **GitHub Actions** — Automated CI/CD pipeline
- **Private subnets** — Secure network isolation
- **CloudWatch Logs** — Centralized logging

## Documentation

See [infrastructure/README.md](infrastructure/README.md) for complete deployment instructions, architecture details, and best practices.
