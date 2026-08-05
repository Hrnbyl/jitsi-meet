# ==============================================================================
# AMAZON EKS MODULE
# Purpose: Deploys a managed Kubernetes cluster control plane and worker nodes.
# ==============================================================================
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  enable_cluster_creator_admin_permissions = true # In production often disabled or restricted to specific IAM role for improved security.
  cluster_endpoint_public_access           = true # In production often disabled or restricted to specific IP addresses for improved security.

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    jitsi_nodes = {
      min_size     = 2
      max_size     = 4
      desired_size = 4

      ami_type       = "AL2_x86_64"
      instance_types = ["t3.micro"]
      capacity_type  = "ON_DEMAND"

      labels = {
        role = "jitsi-worker"
      }
    }
  }

  tags = {
    Environment = "Dev"
    Project     = "Jitsi-Meet"
  }
}
