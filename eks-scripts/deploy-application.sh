#!/bin/bash
# Script to deploy the retail store application to EKS

# Exit on error
set -e

# Set variables
CLUSTER_NAME="scaler-eks-cluster"
REGION="us-east-1"

echo "Deploying retail store application to EKS cluster: $CLUSTER_NAME"

# Ensure we're connected to the right cluster
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# Create ECR repositories for each service
echo "Creating ECR repositories..."
for SERVICE in ui catalog cart checkout orders; do
  echo "Creating repository for $SERVICE..."
  aws ecr create-repository --repository-name retail-store/$SERVICE || true
done

# Set AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Login to ECR
echo "Logging in to Amazon ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Build and push Docker images
echo "Building and pushing Docker images..."
cd ..

# Build and push each service
SERVICES=("ui" "catalog" "cart" "checkout" "orders")
for SERVICE in "${SERVICES[@]}"; do
  echo "Building $SERVICE service..."
  cd src/$SERVICE
  docker build -t retail-store/$SERVICE:latest .
  
  echo "Tagging $SERVICE image..."
  docker tag retail-store/$SERVICE:latest $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/retail-store/$SERVICE:latest
  
  echo "Pushing $SERVICE image to ECR..."
  docker push $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/retail-store/$SERVICE:latest
  
  cd ../..
  echo "$SERVICE service pushed to ECR successfully"
  echo "-------------------------------------------"
done

# Update Kubernetes manifests with correct image URLs
echo "Updating Kubernetes manifests..."
cd k8s-manifests

for file in *-deployment.yaml; do
  echo "Processing $file..."
  sed -i "s/\${AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" "$file"
  sed -i "s/\${AWS_REGION}/$REGION/g" "$file"
done

# Create namespace
echo "Creating namespace..."
kubectl create namespace retail-store || true

# Apply Kubernetes manifests
echo "Deploying services..."
kubectl apply -f retail-namespace.yaml
kubectl apply -f ui-deployment.yaml
kubectl apply -f catalog-deployment.yaml
kubectl apply -f cart-deployment.yaml
kubectl apply -f checkout-deployment.yaml
kubectl apply -f orders-deployment.yaml

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod --all -n retail-store --timeout=300s

echo "Application deployed successfully!"
echo "To check status: kubectl get pods -n retail-store"
echo "To get the UI service URL: kubectl get service ui -n retail-store"

# Get the UI service URL
echo "UI Service URL:"
kubectl get service ui -n retail-store