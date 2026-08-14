#!/usr/bin/env bash
set -e

echo "=================================================="
echo " ⚠️ STARTING FULL INFRASTRUCTURE NUKE"
echo "=================================================="

AWS_REGION="ap-south-1"
CLUSTER_NAME="jitsi-eks-cluster"
NAMESPACE="jitsi"
POLICY_NAME="EKS_Combined_ALB_Route53_Policy"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

# 1. Uninstall Helm & Ingress (Triggers AWS Load Balancer Deletion)
echo "🧹 Step 1: Uninstalling Jitsi & Ingress..."
helm uninstall jitsi-release -n "$NAMESPACE" 2>/dev/null || true
kubectl delete ingress --all -n "$NAMESPACE" 2>/dev/null || true
kubectl delete svc --all -n "$NAMESPACE" 2>/dev/null || true

# 2. Uninstall AWS Load Balancer Controller
echo "🧹 Step 2: Uninstalling AWS Load Balancer Controller..."
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

echo "⏳ Step 3: Pausing 60 seconds to allow AWS to detach ENIs..."
sleep 60

# 3. Destroy Terraform Resources
echo "🔥 Step 4: Running Terraform Destroy..."
cd jitsi-infra/terraform
terraform destroy -auto-approve
cd ../..

# 4. Fail-Safe: Force Delete ANY Remaining VPCs created by Terraform
echo "☢️ Step 5: Fail-Safe VPC Cleanup (Destroying ghost resources)..."
NON_DEFAULT_VPCS=$(aws ec2 describe-vpcs --region $AWS_REGION --query "Vpcs[?IsDefault==\`false\`].VpcId" --output text)

for VPC_ID in $NON_DEFAULT_VPCS; do
  echo "Force cleaning VPC: $VPC_ID"
  
  # Delete leftover ENIs
  ENIS=$(aws ec2 describe-network-interfaces --region $AWS_REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
  for eni in $ENIS; do aws ec2 delete-network-interface --region $AWS_REGION --network-interface-id "$eni" || true; done

  # Delete leftover Security Groups
  SGS=$(aws ec2 describe-security-groups --region $AWS_REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for sg in $SGS; do aws ec2 delete-security-group --region $AWS_REGION --group-id "$sg" || true; done

  # Delete leftover Subnets
  SUBNETS=$(aws ec2 describe-subnets --region $AWS_REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
  for sub in $SUBNETS; do aws ec2 delete-subnet --region $AWS_REGION --subnet-id "$sub" || true; done

  # Delete leftover IGWs
  IGWS=$(aws ec2 describe-internet-gateways --region $AWS_REGION --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
  for igw in $IGWS; do 
    aws ec2 detach-internet-gateway --region $AWS_REGION --internet-gateway-id "$igw" --vpc-id "$VPC_ID" || true
    aws ec2 delete-internet-gateway --region $AWS_REGION --internet-gateway-id "$igw" || true
  done

  # Finally, delete VPC
  aws ec2 delete-vpc --region $AWS_REGION --vpc-id "$VPC_ID" || true
done

# 5. IAM & Log Cleanup
echo "🧹 Step 6: Removing IAM Policies, Logs, and State files..."
aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null || true
aws logs delete-log-group --log-group-name "/aws/eks/$CLUSTER_NAME/cluster" --region "$AWS_REGION" 2>/dev/null || true

# ONLY delete state because we manually guaranteed the VPC is gone above
rm -rf jitsi-infra/terraform/.terraform* 
rm -rf jitsi-infra/terraform/terraform.tfstate* 

echo "=================================================="
echo " ✨ TEARDOWN COMPLETE! YOUR AWS ACCOUNT IS 100% CLEAN."
echo "=================================================="