# AWS EKS Deployment Guide - Step by Step

This guide provides detailed instructions for setting up an Amazon EKS cluster with EC2 instances as worker nodes, all using the AWS CLI.

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- kubectl command-line tool
- An existing VPC with public and private subnets

## Step 1: Install kubectl on Ubuntu

```bash
# Download kubectl binary from Amazon EKS (amd64 architecture)
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.0/2025-05-01/bin/linux/amd64/kubectl
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.0/2025-05-01/bin/linux/amd64/kubectl.sha256

# Make kubectl executable
chmod +x ./kubectl

# Move kubectl to bin directory and add to PATH
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH

# Add to bashrc for persistence
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc

# Verify installation
kubectl version --client
```

## Step 2: Create IAM Roles for EKS

```bash
# Create EKS cluster role
aws iam create-role \
  --role-name ScalerEKSClusterRole \
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

# Attach required policies to the cluster role
aws iam attach-role-policy \
  --role-name ScalerEKSClusterRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# Create EKS node role
aws iam create-role \
  --role-name ScalerEKSNodeRole \
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
  --role-name ScalerEKSNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name ScalerEKSNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy \
  --role-name ScalerEKSNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

## Step 3: Create EKS Cluster

```bash
# Set variables
VPC_ID="vpc-00ca5a956e4f124f2"
PUBLIC_SUBNET_1="subnet-01c39edbf3f4c6b5b"
PUBLIC_SUBNET_2="subnet-0c75f1b5695348705"
CLUSTER_ROLE_ARN=$(aws iam get-role --role-name ScalerEKSClusterRole --query "Role.Arn" --output text)

# Create EKS cluster
aws eks create-cluster \
  --name scaler-eks-cluster \
  --role-arn $CLUSTER_ROLE_ARN \
  --resources-vpc-config subnetIds=$PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2,securityGroupIds= \
  --kubernetes-version 1.27

# Wait for cluster to be created (this may take 10-15 minutes)
aws eks wait cluster-active --name scaler-eks-cluster

# Update kubeconfig to connect to the cluster
aws eks update-kubeconfig --name scaler-eks-cluster --region us-east-1

# Verify connection
kubectl get svc
```

## Step 4: Launch EC2 Instances for Worker Nodes

```bash
# Get the latest Amazon Linux 2 AMI optimized for EKS
AMI_ID=$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/1.27/amazon-linux-2/recommended/image_id --query "Parameter.Value" --output text)

# Create security group for worker nodes
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name ScalerEKSNodeSG \
  --description "Security group for EKS worker nodes" \
  --vpc-id $VPC_ID \
  --query "GroupId" --output text)

# Allow all traffic within the security group
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol all \
  --source-group $SECURITY_GROUP_ID

# Allow SSH access from anywhere (for demo purposes only - restrict in production)
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# Create key pair for SSH access
aws ec2 create-key-pair \
  --key-name ScalerEKSKey \
  --query "KeyMaterial" \
  --output text > ScalerEKSKey.pem

# Set proper permissions for the key file
chmod 400 ScalerEKSKey.pem

# Create IAM instance profile for the node role
aws iam create-instance-profile --instance-profile-name ScalerEKSNodeInstanceProfile
aws iam add-role-to-instance-profile --instance-profile-name ScalerEKSNodeInstanceProfile --role-name ScalerEKSNodeRole

# Get cluster security group ID
CLUSTER_SG=$(aws eks describe-cluster --name scaler-eks-cluster --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

# Allow communication between the cluster and worker nodes
aws ec2 authorize-security-group-ingress \
  --group-id $CLUSTER_SG \
  --protocol all \
  --source-group $SECURITY_GROUP_ID

aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol all \
  --source-group $CLUSTER_SG

# Create user data script for node bootstrap
cat > node-userdata.sh << EOF
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh scaler-eks-cluster
EOF

# Launch first EC2 instance
INSTANCE_1_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.medium \
  --key-name ScalerEKSKey \
  --security-group-ids $SECURITY_GROUP_ID \
  --subnet-id $PUBLIC_SUBNET_1 \
  --user-data file://node-userdata.sh \
  --iam-instance-profile Name=ScalerEKSNodeInstanceProfile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ScalerEKSNode1}]' \
  --query "Instances[0].InstanceId" \
  --output text)

# Launch second EC2 instance
INSTANCE_2_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.medium \
  --key-name ScalerEKSKey \
  --security-group-ids $SECURITY_GROUP_ID \
  --subnet-id $PUBLIC_SUBNET_2 \
  --user-data file://node-userdata.sh \
  --iam-instance-profile Name=ScalerEKSNodeInstanceProfile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ScalerEKSNode2}]' \
  --query "Instances[0].InstanceId" \
  --output text)

# Wait for instances to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_1_ID $INSTANCE_2_ID

echo "EC2 instances launched: $INSTANCE_1_ID $INSTANCE_2_ID"
```

## Step 5: Configure Worker Nodes to Join the EKS Cluster

```bash
# Create aws-auth ConfigMap to allow worker nodes to join the cluster
cat > aws-auth-cm.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: $(aws iam get-role --role-name ScalerEKSNodeRole --query "Role.Arn" --output text)
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
EOF

# Apply the ConfigMap
kubectl apply -f aws-auth-cm.yaml

# Wait for nodes to register with the cluster
echo "Waiting for nodes to join the cluster..."
sleep 60

# Verify nodes are registered
kubectl get nodes
```

## Step 6: Deploy the Retail Store Application

```bash
# Create ECR repositories for each service
for SERVICE in ui catalog cart checkout orders; do
  aws ecr create-repository --repository-name retail-store/$SERVICE
done

# Build and push Docker images
./build-and-push.sh

# Create namespace
kubectl create namespace retail-store

# Apply Kubernetes manifests
kubectl apply -f k8s-manifests/ui-deployment.yaml
kubectl apply -f k8s-manifests/catalog-deployment.yaml
kubectl apply -f k8s-manifests/cart-deployment.yaml
kubectl apply -f k8s-manifests/checkout-deployment.yaml
kubectl apply -f k8s-manifests/orders-deployment.yaml

# Check deployment status
kubectl get pods -n retail-store
kubectl get services -n retail-store
```

## Step 7: Access the Application

```bash
# Get the external URL for the UI service
kubectl get service ui -n retail-store

# The EXTERNAL-IP column will show the load balancer URL
# Open this URL in a web browser to access the application
```

## Cleanup

When you're done with the cluster, you can clean up all resources:

```bash
# Delete the application resources
kubectl delete namespace retail-store

# Terminate EC2 instances
aws ec2 terminate-instances --instance-ids $INSTANCE_1_ID $INSTANCE_2_ID

# Delete the EKS cluster
aws eks delete-cluster --name scaler-eks-cluster

# Delete IAM roles and policies
aws iam remove-role-from-instance-profile --instance-profile-name ScalerEKSNodeInstanceProfile --role-name ScalerEKSNodeRole
aws iam delete-instance-profile --instance-profile-name ScalerEKSNodeInstanceProfile

aws iam detach-role-policy --role-name ScalerEKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam detach-role-policy --role-name ScalerEKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam detach-role-policy --role-name ScalerEKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam delete-role --role-name ScalerEKSNodeRole

aws iam detach-role-policy --role-name ScalerEKSClusterRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam delete-role --role-name ScalerEKSClusterRole

# Delete security group
aws ec2 delete-security-group --group-id $SECURITY_GROUP_ID

# Delete key pair
aws ec2 delete-key-pair --key-name ScalerEKSKey
rm ScalerEKSKey.pem
```

## Troubleshooting

If nodes don't join the cluster:
1. Check EC2 instance status and user data script execution in instance logs
2. Verify security group rules allow communication between nodes and control plane
3. Ensure IAM roles have the correct permissions
4. Check aws-auth ConfigMap is correctly configured

If pods don't start:
1. Check pod status: `kubectl describe pod <pod-name> -n retail-store`
2. View container logs: `kubectl logs <pod-name> -n retail-store`
3. Verify ECR repositories are accessible from the nodes

---

## Learn AWS by Doing with Govind

This deployment guide is part of the "Learn AWS by Doing" series. Follow along to gain hands-on experience with AWS services and container orchestration.