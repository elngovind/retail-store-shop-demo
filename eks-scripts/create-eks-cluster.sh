#!/bin/bash
# Script to create an EKS cluster with EC2 worker nodes

# Exit on error
set -e

# Set variables
CLUSTER_NAME="scaler-eks-cluster"
REGION="us-east-1"
VPC_ID="vpc-00ca5a956e4f124f2"
PUBLIC_SUBNET_1="subnet-01c39edbf3f4c6b5b"
PUBLIC_SUBNET_2="subnet-0c75f1b5695348705"
K8S_VERSION="1.27"

echo "Creating EKS cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "VPC: $VPC_ID"
echo "Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"

# Step 1: Create IAM roles
echo "Creating IAM roles..."

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

# Get role ARNs
CLUSTER_ROLE_ARN=$(aws iam get-role --role-name ScalerEKSClusterRole --query "Role.Arn" --output text)
NODE_ROLE_ARN=$(aws iam get-role --role-name ScalerEKSNodeRole --query "Role.Arn" --output text)

echo "Cluster Role ARN: $CLUSTER_ROLE_ARN"
echo "Node Role ARN: $NODE_ROLE_ARN"

# Step 2: Create EKS cluster
echo "Creating EKS cluster (this may take 10-15 minutes)..."
aws eks create-cluster \
  --name $CLUSTER_NAME \
  --role-arn $CLUSTER_ROLE_ARN \
  --resources-vpc-config subnetIds=$PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2 \
  --kubernetes-version $K8S_VERSION

echo "Waiting for cluster to become active..."
aws eks wait cluster-active --name $CLUSTER_NAME

# Step 3: Create security group for worker nodes
echo "Creating security group for worker nodes..."
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name ScalerEKSNodeSG \
  --description "Security group for EKS worker nodes" \
  --vpc-id $VPC_ID \
  --query "GroupId" --output text)

echo "Security Group ID: $SECURITY_GROUP_ID"

# Allow all traffic within the security group
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol all \
  --source-group $SECURITY_GROUP_ID

# Allow SSH access from anywhere (for demo purposes only)
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# Get cluster security group ID
CLUSTER_SG=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

# Allow communication between the cluster and worker nodes
aws ec2 authorize-security-group-ingress \
  --group-id $CLUSTER_SG \
  --protocol all \
  --source-group $SECURITY_GROUP_ID

aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol all \
  --source-group $CLUSTER_SG

# Step 4: Create key pair for SSH access
echo "Creating key pair for SSH access..."
aws ec2 create-key-pair \
  --key-name ScalerEKSKey \
  --query "KeyMaterial" \
  --output text > ScalerEKSKey.pem

chmod 400 ScalerEKSKey.pem

# Step 5: Create IAM instance profile for the node role
echo "Creating IAM instance profile..."
aws iam create-instance-profile --instance-profile-name ScalerEKSNodeInstanceProfile
aws iam add-role-to-instance-profile --instance-profile-name ScalerEKSNodeInstanceProfile --role-name ScalerEKSNodeRole

# Step 6: Get the latest Amazon Linux 2 AMI optimized for EKS
echo "Getting EKS-optimized AMI ID..."
AMI_ID=$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/$K8S_VERSION/amazon-linux-2/recommended/image_id --query "Parameter.Value" --output text)
echo "AMI ID: $AMI_ID"

# Step 7: Create user data script for node bootstrap
echo "Creating bootstrap script..."
cat > node-userdata.sh << EOF
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh $CLUSTER_NAME
EOF

# Step 8: Launch EC2 instances
echo "Launching EC2 instances..."
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

echo "EC2 instance 1: $INSTANCE_1_ID"
echo "EC2 instance 2: $INSTANCE_2_ID"

echo "Waiting for instances to be running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_1_ID $INSTANCE_2_ID

# Step 9: Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# Step 10: Create aws-auth ConfigMap
echo "Creating aws-auth ConfigMap..."
cat > aws-auth-cm.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: $NODE_ROLE_ARN
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
EOF

kubectl apply -f aws-auth-cm.yaml

echo "Waiting for nodes to join the cluster..."
sleep 60

echo "Checking node status..."
kubectl get nodes

echo "EKS cluster setup complete!"
echo "Cluster name: $CLUSTER_NAME"
echo "Worker nodes: $INSTANCE_1_ID, $INSTANCE_2_ID"
echo "To access the cluster: kubectl get nodes"