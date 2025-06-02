# Persistent Volume Demo for EKS

This guide demonstrates how to use persistent volumes in Amazon EKS to store data that persists beyond the lifecycle of pods.

## Prerequisites

- An EKS cluster with the AWS EBS CSI driver installed
- kubectl configured to connect to your cluster

## Step 1: Install the AWS EBS CSI Driver

First, we need to install the AWS EBS CSI driver to provision EBS volumes:

```bash
# Create an IAM policy for the EBS CSI driver
aws iam create-policy \
  --policy-name AmazonEKS_EBS_CSI_Driver_Policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ec2:CreateSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:CreateTags"
        ],
        "Resource": [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ],
        "Condition": {
          "StringEquals": {
            "ec2:CreateAction": [
              "CreateVolume",
              "CreateSnapshot"
            ]
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteTags"
        ],
        "Resource": [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:CreateVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "aws:RequestTag/ebs.csi.aws.com/cluster": "true"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:CreateVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "aws:RequestTag/CSIVolumeName": "*"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "ec2:ResourceTag/CSIVolumeName": "*"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteVolume"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "ec2:ResourceTag/kubernetes.io/created-for/pvc/name": "*"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteSnapshot"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "ec2:ResourceTag/CSIVolumeSnapshotName": "*"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteSnapshot"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
          }
        }
      }
    ]
  }'

# Create an IAM role for the EBS CSI driver
# Create an IAM role for the EBS CSI driver service account
aws iam create-role \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/XXXXXXXXXXXXXXXXXXXXXXXXX"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "oidc.eks.us-east-1.amazonaws.com/id/XXXXXXXXXXXXXXXXXXXXXXXXX:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  }'

# Attach the policy to the role
aws iam attach-role-policy \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AmazonEKS_EBS_CSI_Driver_Policy

# Create the service account
kubectl create serviceaccount ebs-csi-controller-sa -n kube-system

# Annotate the service account with the IAM role
kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKS_EBS_CSI_DriverRole

# Install the EBS CSI driver using Helm
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm upgrade --install aws-ebs-csi-driver \
  --namespace kube-system \
  aws-ebs-csi-driver/aws-ebs-csi-driver
```

## Step 2: Deploy the Persistent Volume Demo

Apply the persistent volume demo manifest:

```bash
kubectl apply -f k8s-manifests/persistent-volume-demo.yaml
```

This will create:
1. A StorageClass for EBS volumes
2. Two PersistentVolumeClaims
3. A MySQL deployment using one PVC
4. A data-writer deployment using another PVC

## Step 3: Verify the Persistent Volumes

Check that the PVCs are bound:

```bash
kubectl get pvc -n retail-store
```

You should see output like:
```
NAME              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
mysql-data-pvc    Bound    pvc-a1b2c3d4-e5f6-7890-a1b2-c3d4e5f67890   5Gi        RWO            ebs-sc         1m
shared-data-pvc   Bound    pvc-b2c3d4e5-f6g7-8901-b2c3-d4e5f6g78901   1Gi        RWO            ebs-sc         1m
```

## Step 4: Demonstrate Data Persistence

1. Check the data being written by the data-writer pod:

```bash
# Get the pod name
DATA_WRITER_POD=$(kubectl get pod -n retail-store -l app=data-writer -o jsonpath='{.items[0].metadata.name}')

# View the timestamps file
kubectl exec -n retail-store $DATA_WRITER_POD -- cat /data/timestamp.txt
```

2. Delete the data-writer pod and let Kubernetes recreate it:

```bash
kubectl delete pod -n retail-store $DATA_WRITER_POD
```

3. Wait for the new pod to be created:

```bash
kubectl get pods -n retail-store -l app=data-writer -w
```

4. Check that the data persists in the new pod:

```bash
# Get the new pod name
NEW_DATA_WRITER_POD=$(kubectl get pod -n retail-store -l app=data-writer -o jsonpath='{.items[0].metadata.name}')

# View the timestamps file again
kubectl exec -n retail-store $NEW_DATA_WRITER_POD -- cat /data/timestamp.txt
```

You should see that the timestamps from before the pod was deleted are still there, demonstrating that the data persists beyond the lifecycle of the pod.

## Step 5: Clean Up

When you're done with the demo, you can clean up the resources:

```bash
kubectl delete -f k8s-manifests/persistent-volume-demo.yaml
```

## Key Concepts Demonstrated

1. **StorageClass**: Defines the type of storage to provision (EBS GP3 volumes)
2. **PersistentVolumeClaim (PVC)**: Requests storage from the cluster
3. **Deployment with Volume Mounts**: Shows how to use the PVC in a pod
4. **Data Persistence**: Demonstrates that data survives pod restarts

This demo shows how EKS can use AWS EBS volumes for persistent storage, which is essential for stateful applications like databases.