#!/bin/bash

# Set your AWS account ID and region
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=$(aws configure get region)

echo "Using AWS Account ID: $AWS_ACCOUNT_ID"
echo "Using AWS Region: $AWS_REGION"

# Replace placeholders in YAML files
for file in *.yaml; do
  echo "Processing $file..."
  sed -i '' "s/\${AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" "$file"
  sed -i '' "s/\${AWS_REGION}/$AWS_REGION/g" "$file"
done

# Apply Kubernetes manifests
echo "Creating namespace..."
kubectl apply -f retail-namespace.yaml

echo "Deploying services..."
kubectl apply -f ui-deployment.yaml
kubectl apply -f catalog-deployment.yaml
kubectl apply -f cart-deployment.yaml
kubectl apply -f checkout-deployment.yaml
kubectl apply -f orders-deployment.yaml

echo "Deployment complete!"
echo "To check status, run: kubectl get pods -n retail-store"
echo "To get the UI service URL, run: kubectl get service ui -n retail-store"