#!/bin/bash

# Set your AWS account ID and region
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=$(aws configure get region)

echo "Using AWS Account ID: $AWS_ACCOUNT_ID"
echo "Using AWS Region: $AWS_REGION"

# Login to ECR
echo "Logging in to Amazon ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and push each service
SERVICES=("ui" "catalog" "cart" "checkout" "orders")

for SERVICE in "${SERVICES[@]}"; do
  echo "Building $SERVICE service..."
  cd src/$SERVICE
  docker build -t retail-store/$SERVICE:latest .
  
  echo "Tagging $SERVICE image..."
  docker tag retail-store/$SERVICE:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/$SERVICE:latest
  
  echo "Pushing $SERVICE image to ECR..."
  docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/$SERVICE:latest
  
  cd ../..
  echo "$SERVICE service pushed to ECR successfully"
  echo "-------------------------------------------"
done

echo "All services built and pushed to ECR"