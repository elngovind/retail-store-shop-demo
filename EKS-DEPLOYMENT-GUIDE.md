# Deploying Retail Store Demo on Amazon EKS

This guide provides step-by-step instructions for deploying the Retail Store Demo application on Amazon EKS using the AWS Console.

## Prerequisites

- AWS Account with appropriate permissions
- Docker installed locally
- Git repository cloned: `https://github.com/elngovind/retail-store-shop-demo.git`

## Step 1: Create an Amazon EKS Cluster

1. **Sign in to AWS Console**
   - Go to https://console.aws.amazon.com
   - Sign in with your AWS account

2. **Create EKS Cluster**
   - Navigate to Amazon EKS service
   - Click "Create cluster"
   - Enter cluster name: `retail-store-cluster`
   - Select Kubernetes version: `1.27` or latest
   - Configure networking:
     - Create new VPC or select existing
     - Select at least 2 subnets in different AZs
   - Configure security:
     - Create new IAM role or use existing with EKS permissions
   - Review and create cluster (takes ~15 minutes)

## Step 2: Create Node Group

1. **Add Node Group to Cluster**
   - In your cluster, go to "Compute" tab
   - Click "Add node group"
   - Name: `retail-store-nodes`
   - Create IAM role for nodes with these policies:
     - AmazonEKSWorkerNodePolicy
     - AmazonEKS_CNI_Policy
     - AmazonEC2ContainerRegistryReadOnly
   - Instance type: `t3.medium`
   - Disk size: `20` GB
   - Desired capacity: `2` nodes
   - Maximum size: `4` nodes
   - Minimum size: `1` node
   - Create node group (takes ~5 minutes)

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

## Step 5: Build and Push Docker Images

1. **Build Docker Images Locally**
   ```bash
   cd /path/to/retail-store-shop-demo
   docker build -t ui:latest ./src/ui
   docker build -t catalog:latest ./src/catalog
   docker build -t cart:latest ./src/cart
   docker build -t checkout:latest ./src/checkout
   docker build -t orders:latest ./src/orders
   ```

2. **Push Images to ECR**
   - Click "View push commands" in each ECR repository
   - Follow the instructions to tag and push each image

## Step 6: Create Kubernetes Manifests

Save the following YAML files to your repository:

### Namespace
```yaml
# retail-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: retail-store
```

### UI Service
```yaml
# ui-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ui
  namespace: retail-store
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ui
  template:
    metadata:
      labels:
        app: ui
    spec:
      containers:
      - name: ui
        image: <your-account-id>.dkr.ecr.<region>.amazonaws.com/retail-store/ui:latest
        ports:
        - containerPort: 8080
        env:
        - name: CATALOG_SERVICE_URL
          value: "http://catalog:8080"
        - name: CART_SERVICE_URL
          value: "http://cart:8080"
        - name: CHECKOUT_SERVICE_URL
          value: "http://checkout:8080"
        - name: ORDERS_SERVICE_URL
          value: "http://orders:8080"
---
apiVersion: v1
kind: Service
metadata:
  name: ui
  namespace: retail-store
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: ui
```

### Catalog Service
```yaml
# catalog-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: retail-store
spec:
  replicas: 2
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
    spec:
      containers:
      - name: catalog
        image: <your-account-id>.dkr.ecr.<region>.amazonaws.com/retail-store/catalog:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: catalog
  namespace: retail-store
spec:
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: catalog
```

### Cart Service
```yaml
# cart-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart
  namespace: retail-store
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cart
  template:
    metadata:
      labels:
        app: cart
    spec:
      containers:
      - name: cart
        image: <your-account-id>.dkr.ecr.<region>.amazonaws.com/retail-store/cart:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: cart
  namespace: retail-store
spec:
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: cart
```

### Checkout Service
```yaml
# checkout-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout
  namespace: retail-store
spec:
  replicas: 2
  selector:
    matchLabels:
      app: checkout
  template:
    metadata:
      labels:
        app: checkout
    spec:
      containers:
      - name: checkout
        image: <your-account-id>.dkr.ecr.<region>.amazonaws.com/retail-store/checkout:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: checkout
  namespace: retail-store
spec:
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: checkout
```

### Orders Service
```yaml
# orders-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
  namespace: retail-store
spec:
  replicas: 2
  selector:
    matchLabels:
      app: orders
  template:
    metadata:
      labels:
        app: orders
    spec:
      containers:
      - name: orders
        image: <your-account-id>.dkr.ecr.<region>.amazonaws.com/retail-store/orders:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: orders
  namespace: retail-store
spec:
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: orders
```

## Step 7: Apply Kubernetes Manifests

1. **Apply Manifests Using kubectl**
   ```bash
   kubectl apply -f retail-namespace.yaml
   kubectl apply -f ui-deployment.yaml
   kubectl apply -f catalog-deployment.yaml
   kubectl apply -f cart-deployment.yaml
   kubectl apply -f checkout-deployment.yaml
   kubectl apply -f orders-deployment.yaml
   ```

## Step 8: Verify Deployment

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

## Step 9: Configure Ingress (Optional)

1. **Install NGINX Ingress Controller**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/aws/deploy.yaml
   ```

2. **Create Ingress Resource**
   ```yaml
   # retail-ingress.yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: retail-ingress
     namespace: retail-store
     annotations:
       kubernetes.io/ingress.class: nginx
   spec:
     rules:
     - http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: ui
               port:
                 number: 80
   ```

3. **Apply Ingress**
   ```bash
   kubectl apply -f retail-ingress.yaml
   ```

## Step 10: Monitor Your Application

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