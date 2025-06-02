# Deploying Retail Store Demo on Amazon EKS

This guide provides step-by-step instructions for deploying the Retail Store Demo application on Amazon EKS using the AWS Console.

## Prerequisites

- AWS Account with appropriate permissions
- Docker installed locally
- Git repository cloned: `https://github.com/elngovind/retail-store-shop-demo.git`
- AWS CLI installed and configured

## Step 1: Create an Amazon EKS Cluster using AWS CLI

```bash
# Set variables
CLUSTER_NAME="retail-store-cluster"
REGION="us-east-1"
VPC_ID="vpc-00ca5a956e4f124f2"
PUBLIC_SUBNET_1="subnet-01c39edbf3f4c6b5b"
PUBLIC_SUBNET_2="subnet-0c75f1b5695348705"

# Create IAM role for EKS cluster
aws iam create-role \
  --role-name EKSClusterRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "eks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'

# Attach required policy to the role
aws iam attach-role-policy \
  --role-name EKSClusterRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# Get the role ARN
CLUSTER_ROLE_ARN=$(aws iam get-role --role-name EKSClusterRole --query "Role.Arn" --output text)

# Create EKS cluster
aws eks create-cluster \
  --name $CLUSTER_NAME \
  --role-arn $CLUSTER_ROLE_ARN \
  --resources-vpc-config subnetIds=$PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2 \
  --kubernetes-version 1.33

# Wait for cluster to be created (this takes 10-15 minutes)
aws eks wait cluster-active --name $CLUSTER_NAME
```

## Step 2: Create Node Group using AWS CLI

```bash
# Create IAM role for worker nodes
aws iam create-role \
  --role-name EKSNodeRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'

# Attach required policies to the node role
aws iam attach-role-policy \
  --role-name EKSNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name EKSNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy \
  --role-name EKSNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# Get the node role ARN
NODE_ROLE_ARN=$(aws iam get-role --role-name EKSNodeRole --query "Role.Arn" --output text)

# Create node group
aws eks create-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name retail-store-nodes \
  --node-role $NODE_ROLE_ARN \
  --subnets $PUBLIC_SUBNET_1 $PUBLIC_SUBNET_2 \
  --instance-types t3.medium \
  --disk-size 20 \
  --scaling-config minSize=1,maxSize=4,desiredSize=2

# Wait for node group to be created (this takes 3-5 minutes)
aws eks wait nodegroup-active \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name retail-store-nodes
```

## Step 3: Configure kubectl to Connect to Your Cluster

1. **Update kubeconfig**
   - In AWS Console, go to your EKS cluster
   - Click "Update kubeconfig for this cluster"
   - Copy the command shown and run in your terminal:
   ```bash
   aws eks update-kubeconfig --region <region> --name retail-store-cluster
   ```
   - Verify connection:
   ```bash
   kubectl get nodes
   ```

## Step 4: Create Amazon ECR Repositories

1. **Create ECR Repositories**
   - Go to Amazon ECR in AWS Console
   - Click "Create repository" for each service:
     - `retail-store/ui`
     - `retail-store/catalog`
     - `retail-store/cart`
     - `retail-store/checkout`
     - `retail-store/orders`

   Alternatively, use AWS CLI to create all repositories:
   ```bash
   aws ecr create-repository --repository-name retail-store/ui
   aws ecr create-repository --repository-name retail-store/catalog
   aws ecr create-repository --repository-name retail-store/cart
   aws ecr create-repository --repository-name retail-store/checkout
   aws ecr create-repository --repository-name retail-store/orders
   ```

## Step 5: Build and Push Docker Images

Each service has its own Dockerfile in its respective directory. You can build and push them individually or use the script below to automate the process.

### Option 1: Automated Script

Create a file named `build-and-push.sh` in the repository root:

```bash
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
```

Make the script executable and run it:
```bash
chmod +x build-and-push.sh
./build-and-push.sh
```

### Option 2: Manual Build and Push

Build and push each service individually:

#### UI Service
```bash
# Build UI image
cd src/ui
docker build -t retail-store/ui:latest .

# Tag and push to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
docker tag retail-store/ui:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/ui:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/ui:latest
cd ..
```

#### Catalog Service
```bash
# Build Catalog image
cd src/catalog
docker build -t retail-store/catalog:latest .

# Tag and push to ECR
docker tag retail-store/catalog:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/catalog:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/catalog:latest
cd ..
```

#### Cart Service
```bash
# Build Cart image
cd src/cart
docker build -t retail-store/cart:latest .

# Tag and push to ECR
docker tag retail-store/cart:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/cart:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/cart:latest
cd ..
```

#### Checkout Service
```bash
# Build Checkout image
cd src/checkout
docker build -t retail-store/checkout:latest .

# Tag and push to ECR
docker tag retail-store/checkout:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/checkout:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/checkout:latest
cd ..
```

#### Orders Service
```bash
# Build Orders image
cd src/orders
docker build -t retail-store/orders:latest .

# Tag and push to ECR
docker tag retail-store/orders:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/orders:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store/orders:latest
cd ..
```

## Step 6: Deploy Using Kubernetes Manifests

The repository includes pre-configured Kubernetes manifests in the `k8s-manifests` directory. You can use the provided `deploy.sh` script to automatically deploy all services.

### Option 1: Using the Deployment Script

```bash
cd k8s-manifests
./deploy.sh
```

This script will:
1. Detect your AWS account ID and region
2. Replace placeholders in the YAML files
3. Apply all the Kubernetes manifests in the correct order

### Option 2: Manual Deployment

If you prefer to deploy manually:

1. **Update Image URLs in Manifests**
   
   Replace `${AWS_ACCOUNT_ID}` and `${AWS_REGION}` in the YAML files with your actual values:
   ```bash
   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export AWS_REGION=$(aws configure get region)
   
   # Replace placeholders in YAML files
   for file in k8s-manifests/*.yaml; do
     sed -i '' "s/\${AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" "$file"
     sed -i '' "s/\${AWS_REGION}/$AWS_REGION/g" "$file"
   done
   ```

2. **Apply Manifests Using kubectl**
   ```bash
   kubectl apply -f k8s-manifests/retail-namespace.yaml
   kubectl apply -f k8s-manifests/ui-deployment.yaml
   kubectl apply -f k8s-manifests/catalog-deployment.yaml
   kubectl apply -f k8s-manifests/cart-deployment.yaml
   kubectl apply -f k8s-manifests/checkout-deployment.yaml
   kubectl apply -f k8s-manifests/orders-deployment.yaml
   ```

## Step 7: Verify Deployment

1. **Check Deployments**
   ```bash
   kubectl get deployments -n retail-store
   ```

2. **Check Services**
   ```bash
   kubectl get services -n retail-store
   ```

3. **Get UI Service URL**
   ```bash
   kubectl get service ui -n retail-store
   ```
   - Use the EXTERNAL-IP to access your application

## Step 8: Configure Ingress (Optional)

1. **Install NGINX Ingress Controller**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/aws/deploy.yaml
   ```

2. **Apply Ingress Resource**
   ```bash
   kubectl apply -f k8s-manifests/retail-ingress.yaml
   ```

## Step 9: Monitor Your Application

1. **Check Logs**
   ```bash
   kubectl logs -f deployment/ui -n retail-store
   ```

2. **Monitor Pods**
   ```bash
   kubectl get pods -n retail-store -w
   ```

## Troubleshooting

If you encounter issues:

1. **Check Pod Status**
   ```bash
   kubectl describe pod <pod-name> -n retail-store
   ```

2. **Check Service Connectivity**
   ```bash
   kubectl exec -it <ui-pod-name> -n retail-store -- curl catalog:8080/health
   ```

3. **View Container Logs**
   ```bash
   kubectl logs <pod-name> -n retail-store
   ```

## Cleanup

To delete resources when no longer needed:

```bash
kubectl delete namespace retail-store
```

Then delete the EKS cluster from the AWS Console.

---

## Learn AWS by Doing with Govind

This deployment guide is part of the "Learn AWS by Doing" series. Follow along to gain hands-on experience with AWS services and container orchestration.