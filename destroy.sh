#!/usr/bin/env bash
set -e

echo "=================================================="
echo " ⚠️ STARTING FULL INFRASTRUCTURE TEARDOWN"
echo "=================================================="

AWS_REGION="ap-south-1"
CLUSTER_NAME="jitsi-eks-cluster"
NAMESPACE="jitsi"
POLICY_NAME="EKS_Combined_ALB_Route53_Policy"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

# 1. Uninstall Helm Platform Release & Ingress Resources
echo "--------------------------------------------------"
echo "🧹 Step 1: Uninstalling Jitsi Helm release and deleting Namespace..."
echo "--------------------------------------------------"
helm uninstall jitsi-release -n "$NAMESPACE" || true
kubectl delete ingress --all -n "$NAMESPACE" || true
kubectl delete svc --all -n "$NAMESPACE" || true
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true || true

# 2. Uninstall AWS Load Balancer Controller
echo "--------------------------------------------------"
echo "🧹 Step 2: Uninstalling AWS Load Balancer Controller..."
echo "--------------------------------------------------"
helm uninstall aws-load-balancer-controller -n kube-system || true

# 3. Wait for AWS Dynamic Load Balancer & Security Group Teardown
echo "--------------------------------------------------"
echo "⏳ Step 3: Pausing 120 seconds to allow AWS to delete dynamic ALBs/NLBs..."
echo "--------------------------------------------------"
sleep 120

# 4. Remove IAM Service Account
echo "--------------------------------------------------"
echo "🧹 Step 4: Deleting IAM Service Account..."
echo "--------------------------------------------------"
eksctl delete iamserviceaccount \
    --cluster="$CLUSTER_NAME" \
    --namespace=kube-system \
    --name=aws-load-balancer-controller || true

# 5. Destroy Terraform Resources
echo "--------------------------------------------------"
echo "🔥 Step 5: Destroying VPC, EKS, and Terraform resources..."
echo "--------------------------------------------------"
cd jitsi-infra/terraform
terraform destroy -auto-approve
cd ..

# 6. Delete IAM Policy
echo "--------------------------------------------------"
echo "🧹 Step 6: Removing IAM Policy..."
echo "--------------------------------------------------"
aws iam delete-policy --policy-arn "$POLICY_ARN" || true

echo "=================================================="
echo " ✨ TEARDOWN COMPLETE! YOUR AWS ACCOUNT IS CLEAN."
echo "=================================================="