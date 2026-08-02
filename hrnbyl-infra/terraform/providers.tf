# ==============================================================================
# TERRAFORM CONFIGURATION BLOCK
# Purpose: Declares which external plugins (providers) are required for this project
# and sets the required minimum version of Terraform.
# ==============================================================================
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95.0" # Updated to satisfy all modules
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}

# ==============================================================================
# AWS PROVIDER SETTINGS
# Purpose: Defines which AWS region to deploy into and attaches default tags
# to every single resource created by Terraform for tracking.
# ==============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "Production-Stage"
      Project     = "Jitsi-Meet-DevOps"
      ManagedBy   = "Terraform"
    }
  }
}

# ==============================================================================
# KUBERNETES PROVIDER SETTINGS
# Purpose: Configures authentication tokens so Terraform can communicate with 
# the newly created Amazon EKS cluster securely using local AWS CLI credentials.
# ==============================================================================

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# ==============================================================================
# HELM PROVIDER SETTINGS
# Purpose: Configures Helm to deploy applications into the EKS cluster.
# ==============================================================================

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}
