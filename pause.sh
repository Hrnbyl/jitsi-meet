#!/usr/bin/env bash
set -e

echo "=================================================="
echo " ⏸️ STARTING INFRASTRUCTURE PAUSE (COST-SAVER)"
echo "=================================================="

NAMESPACE="jitsi"

# 1. Uninstall Helm & Ingress (Triggers AWS Load Balancer Deletion)
echo "--------------------------------------------------"
echo "🧹 Step 1: Uninstalling Jitsi & Ingress to remove ALBs/NLBs..."
echo "--------------------------------------------------"
helm uninstall jitsi-release -n "$NAMESPACE" 2>/dev/null || true
kubectl delete ingress --all -n "$NAMESPACE" 2>/dev/null || true
kubectl delete svc --all -n "$NAMESPACE" 2>/dev/null || true

# 2. Uninstall AWS Load Balancer Controller
echo "--------------------------------------------------"
echo "🧹 Step 2: Uninstalling AWS Load Balancer Controller..."
echo "--------------------------------------------------"
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

# 3. Wait for AWS Dynamic Load Balancer & ENI Teardown
echo "--------------------------------------------------"
echo "⏳ Step 3: Pausing 60 seconds to allow AWS to detach ENIs..."
echo "--------------------------------------------------"
sleep 60

# 4. Target Destroy Expensive Resources Only
echo "--------------------------------------------------"
echo "🔥 Step 4: Destroying EKS Cluster & NAT Gateways (Keeping VPC)..."
echo "--------------------------------------------------"
cd jitsi-infra/terraform

# Destroy EKS to stop Control Plane and Node (EC2) billing
terraform destroy -target="module.eks" -auto-approve

# Destroy NAT Gateways to stop hourly NAT billing
terraform destroy -target="module.vpc.aws_nat_gateway.this" -target="module.vpc.aws_eip.nat" -auto-approve || true

cd ../..

echo "=================================================="
echo " ✨ PAUSE COMPLETE! EKS & LBs DESTROYED, VPC SAVED."
echo " Note: We intentionally did NOT delete terraform.tfstate."
echo " To resume later, simply run your standard deploy.sh script."
echo "=================================================="