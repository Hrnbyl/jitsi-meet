#!/usr/bin/env bash
set -e

echo "=================================================="
echo " 🚀 STARTING JITSI MEET INFRASTRUCTURE DEPLOYMENT"
echo "=================================================="

# 1. Environment & Pre-checks
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="ap-south-1"
CLUSTER_NAME="jitsi-eks-cluster"
NAMESPACE="jitsi"
POLICY_NAME="EKS_Combined_ALB_Route53_Policy"

echo "📍 AWS Account ID: $AWS_ACCOUNT_ID"
echo "📍 AWS Region:     $AWS_REGION"
echo "📍 Cluster Name:   $CLUSTER_NAME"

# 2. Provision Infrastructure via Terraform
echo "--------------------------------------------------"
echo "📦 Step 1: Provisioning VPC, EKS, and ACM via Terraform..."
echo "--------------------------------------------------"
cd terraform
terraform init
terraform apply -auto-approve
cd ..

# 3. Kubeconfig Configuration
echo "--------------------------------------------------"
echo "🔑 Step 2: Updating local Kubeconfig for EKS..."
echo "--------------------------------------------------"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# 4. IAM Policy Creation (if missing)
echo "--------------------------------------------------"
echo "🛡️ Step 3: Checking and attaching IAM Policy..."
echo "--------------------------------------------------"
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)

if [ -z "$POLICY_ARN" ]; then
    echo "Creating IAM Policy: $POLICY_NAME..."
    POLICY_ARN=$(aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file://iam_policy.json \
        --query "Policy.Arn" --output text)
fi

echo "Policy ARN: $POLICY_ARN"

# 5. Enable OIDC & Create IAM Service Account (IRSA)
echo "--------------------------------------------------"
echo "⚙️ Step 4: Configuring OIDC and IAM ServiceAccount..."
echo "--------------------------------------------------"
eksctl utils associate-iam-oidc-provider \
    --region="$AWS_REGION" \
    --cluster="$CLUSTER_NAME" \
    --approve

eksctl create iamserviceaccount \
    --cluster="$CLUSTER_NAME" \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --role-name AmazonEKSLoadBalancerControllerRole \
    --attach-policy-arn="$POLICY_ARN" \
    --override-existing-serviceaccounts \
    --approve

# 6. Install AWS Load Balancer Controller
echo "--------------------------------------------------"
echo "🚢 Step 5: Installing AWS Load Balancer Controller via Helm..."
echo "--------------------------------------------------"
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller

echo "Waiting for AWS Load Balancer Controller rollout..."
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s

# 7. Deploy Jitsi Platform
echo "--------------------------------------------------"
echo "🎛️ Step 6: Deploying Jitsi Meet Platform..."
echo "--------------------------------------------------"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install jitsi-release ./helm/jitsi-chart -n "$NAMESPACE"

echo "=================================================="
echo " ✅ DEPLOYMENT COMPLETE!"
echo "=================================================="
kubectl get pods,svc,ingress -n "$NAMESPACE"