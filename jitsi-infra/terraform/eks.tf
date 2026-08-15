module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.32"

  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true
  create_cloudwatch_log_group              = false
  create_kms_key                           = false
  cluster_encryption_config                = {}

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    jitsi_nodes = {
      min_size     = 1
      max_size     = 3
      desired_size = 2

      ami_type             = "AL2_x86_64"
      instance_types       = ["m7i-flex.large"]
      capacity_type        = "ON_DEMAND"
      bootstrap_extra_args = "--use-max-pods false --kubelet-extra-args '--max-pods=110'"

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
