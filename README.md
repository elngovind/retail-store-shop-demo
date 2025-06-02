# AWS EKS Retail Store Sample Application

This is a comprehensive microservices-based retail store application designed to be deployed on Amazon EKS (Elastic Kubernetes Service). This project demonstrates best practices for deploying containerized applications on Kubernetes in AWS.

## Architecture

The application consists of the following microservices:

- **UI**: Frontend service that provides the user interface and aggregates API calls to other services
- **Catalog**: API for product listings and details (Go)
- **Cart**: API for customer shopping carts (Java/Spring Boot)
- **Checkout**: API to orchestrate the checkout process (Node.js/NestJS)
- **Orders**: API to receive and process customer orders (Java/Spring Boot)
- **Assets**: Service for static assets like images and CSS

## Features

- Complete shopping experience with product browsing, cart management, and checkout
- Microservices architecture with clear separation of concerns
- Multiple language runtimes (Java, Go, Node.js)
- RESTful APIs for communication between services
- Containerized with Docker for easy deployment
- Kubernetes manifests for deployment on Amazon EKS
- Terraform modules for infrastructure provisioning
- Health check endpoints for monitoring and readiness/liveness probes

## Deployment Options

### Local Development with Docker Compose

```bash
cd src/app
docker-compose up
```

### Deploy to Amazon EKS

1. Create an EKS cluster:

```bash
cd terraform/eks/default
terraform init
terraform apply
```

2. Deploy the application:

```bash
cd src/app
helmfile sync
```

## Kubernetes Resources

The application deploys the following Kubernetes resources:

- Deployments for each microservice
- Services for internal and external communication
- ConfigMaps for configuration
- Secrets for sensitive information
- Ingress for external access
- HorizontalPodAutoscalers for scaling

## AWS Services Used

- Amazon EKS for container orchestration
- Amazon ECR for container image storage
- Amazon RDS for database services
- Amazon ElastiCache for caching
- Amazon MQ for messaging
- Amazon CloudWatch for monitoring and logging

## Learn More

This sample application is designed to help you learn about deploying microservices on Amazon EKS. Explore the code, configuration, and infrastructure to understand best practices for cloud-native applications.

---

## Learn AWS by Doing with Govind

This project is part of the "Learn AWS by Doing" series by Govind. Follow along to gain hands-on experience with AWS services and container orchestration.