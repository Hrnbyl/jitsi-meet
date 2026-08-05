# Purpose: Prints the secure URL used by kubectl to communicate with EKS.
output "cluster_endpoint" {
  description = "Endpoint URL for EKS control plane API."
  value       = module.eks.cluster_endpoint
}


# Purpose: Prints the cluster name needed for connecting local AWS CLI.
output "cluster_name" {
  description = "The exact name of the created Kubernetes Cluster."
  value       = module.eks.cluster_name
}

# Purpose: Displays the AWS VPC ID created by Terraform.
output "vpc_id" {
  description = "The ID of the custom VPC created for this deployment."
  value       = module.vpc.vpc_id
}
