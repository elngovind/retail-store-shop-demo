#!/bin/bash
# Script to clean up all resources created for the EKS cluster

# Exit on error
set -e

# Set variables
CLUSTER_NAME="scaler-eks-cluster"
REGION="us-east-1"

echo "Cleaning up EKS cluster: $CLUSTER_NAME"

# Get instance IDs of worker nodes
echo "Finding worker node instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=ScalerEKSNode*" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

echo "Worker node instances: $INSTANCE_IDS"

# Delete the application resources
echo "Deleting application resources..."
kubectl delete namespace retail-store || true

# Terminate EC2 instances
if [ ! -z "$INSTANCE_IDS" ]; then
  echo "Terminating EC2 instances..."
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
  
  echo "Waiting for instances to terminate..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
fi

# Delete the EKS cluster
echo "Deleting EKS cluster..."
aws eks delete-cluster --name $CLUSTER_NAME || true

echo "Waiting for cluster to be deleted..."
sleep 60

# Get security group ID
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=ScalerEKSNodeSG" \
  --query "SecurityGroups[0].GroupId" \
  --output text || echo "")

# Delete IAM roles and policies
echo "Cleaning up IAM resources..."
aws iam remove-role-from-instance-profile --instance-profile-name ScalerEKSNodeInstanceProfile --role-name ScalerEKSNodeRole || true
aws iam delete-instance-profile --instance-profile-name ScalerEKSNodeInstanceProfile || true

aws iam detach-role-policy --role-name ScalerEKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy || true
aws iam detach-role-policy --role-name ScalerEKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy || true
aws iam detach-role-policy --role-name ScalerEKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly || true
aws iam delete-role --role-name ScalerEKSNodeRole || true

aws iam detach-role-policy --role-name ScalerEKSClusterRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy || true
aws iam delete-role --role-name ScalerEKSClusterRole || true

# Delete security group
if [ ! -z "$SECURITY_GROUP_ID" ] && [ "$SECURITY_GROUP_ID" != "None" ]; then
  echo "Deleting security group: $SECURITY_GROUP_ID"
  aws ec2 delete-security-group --group-id $SECURITY_GROUP_ID || true
fi

# Delete key pair
echo "Deleting key pair..."
aws ec2 delete-key-pair --key-name ScalerEKSKey || true
rm -f ScalerEKSKey.pem

echo "Cleanup complete!"