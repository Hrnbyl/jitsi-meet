variable "aws_region" {
  description = "The AWS region where all infrastructure will be provisioned."
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "The name of the Amazon EKS Kubernetes cluster."
  type        = string
  default     = "jitsi-eks-cluster"
}

variable "vpc_cidr" {
  description = "The base network CIDR block for the custom VPC."
  type        = string
  default     = "10.0.0.0/16"
}
