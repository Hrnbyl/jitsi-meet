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
DOMAIN_NAME="meet.hrnbyl.com"

echo "📍 AWS Account ID: $AWS_ACCOUNT_ID"
echo "📍 AWS Region:     $AWS_REGION"
echo "📍 Cluster Name:   $CLUSTER_NAME"

# 2. Provision Infrastructure via Terraform
echo "--------------------------------------------------"
echo "📦 Step 1: Provisioning VPC, EKS, and ACM via Terraform..."
echo "--------------------------------------------------"
cd jitsi-infra/terraform
terraform init
terraform apply -auto-approve
cd ../..

# 3. Dynamically Fetch and Inject ACM Certificate
echo "--------------------------------------------------"
echo "🔍 Step 1.5: Fetching & Injecting ACM Certificate ARN..."
echo "--------------------------------------------------"
CERT_ARN=$(aws acm list-certificates --region "$AWS_REGION" --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'] | sort_by(@, &CreatedAt) | [-1].CertificateArn" --output text)

if [ "$CERT_ARN" == "None" ] || [ -z "$CERT_ARN" ]; then
    echo "❌ ERROR: Could not find an ACM certificate for $DOMAIN_NAME. Did Terraform create it?"
    exit 1
fi

echo "✅ Found New ARN: $CERT_ARN"
echo "🧬 Injecting ARN into Helm values.yaml..."
sed -i "s|alb.ingress.kubernetes.io/certificate-arn:.*|alb.ingress.kubernetes.io/certificate-arn: $CERT_ARN|g" ./jitsi-infra/helm/jitsi-chart/values.yaml

echo "=================================================="
echo " 🛑 DNS VALIDATION CHECK (Must be ISSUED before ALB creates)"
echo "=================================================="
aws acm describe-certificate \
    --region "$AWS_REGION" \
    --certificate-arn "$CERT_ARN" \
    --query "Certificate.DomainValidationOptions[*].[ResourceRecord.Name, ResourceRecord.Value]" \
    --output table
echo "=================================================="
echo "⏳ Pausing for 60 seconds..."
echo "👉 Please copy the CNAME values above and add them to Cloudflare (Grey Cloud / DNS Only)."
echo "   (If you already added them previously, just wait for the timer to finish.)"
sleep 60

# 4. Kubeconfig Configuration
echo "--------------------------------------------------"
echo "🔑 Step 2: Updating local Kubeconfig for EKS..."
echo "--------------------------------------------------"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# 5. IAM Policy Creation
echo "--------------------------------------------------"
echo "🛡️ Step 3: Checking and attaching IAM Policy..."
echo "--------------------------------------------------"
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)

if [ -z "$POLICY_ARN" ]; then
    echo "Creating IAM Policy: $POLICY_NAME..."
    POLICY_ARN=$(aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file://jitsi-infra/iam_policy.json \
        --query "Policy.Arn" --output text)
fi

echo "Policy ARN: $POLICY_ARN"

# 6. Enable OIDC & Create IAM Service Account (IRSA)
echo "--------------------------------------------------"
echo "⚙️ Step 4: Configuring OIDC and IAM ServiceAccount..."
echo "--------------------------------------------------"
eksctl utils associate-iam-oidc-provider \
    --region="$AWS_REGION" \
    --cluster="$CLUSTER_NAME" \
    --approve

# FIX: Force cleanup of stale IAM mappings/CloudFormation stacks from previous runs 
# to prevent the "AccessDenied" WebIdentity error when rebuilding the cluster.
echo "🧹 Cleaning up any stale Service Accounts or IAM mappings..."
kubectl delete sa aws-load-balancer-controller -n kube-system 2>/dev/null || true
eksctl delete iamserviceaccount --cluster="$CLUSTER_NAME" --namespace=kube-system --name=aws-load-balancer-controller 2>/dev/null || true

echo "🏗️ Creating fresh IAM service account mapping..."
eksctl create iamserviceaccount \
    --cluster="$CLUSTER_NAME" \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --role-name AmazonEKSLoadBalancerControllerRole \
    --attach-policy-arn="$POLICY_ARN" \
    --override-existing-serviceaccounts \
    --approve

# 7. Install AWS Load Balancer Controller
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
kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s

# 8. Deploy Jitsi Platform
echo "--------------------------------------------------"
echo "🎛️ Step 6: Deploying Jitsi Meet Platform..."
echo "--------------------------------------------------"
# FIX: Explicitly ensure the namespace exists before deploying to prevent "namespaces not found" error
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install jitsi-release ./jitsi-infra/helm/jitsi-chart -n "$NAMESPACE"

echo "=================================================="
echo " ✅ DEPLOYMENT COMPLETE!"
echo "=================================================="
kubectl get pods,svc,ingress -n "$NAMESPACE"