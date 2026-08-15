terraform {
  backend "s3" {
    bucket  = "jitsimeet-terraform-state-12345"
    key     = "jitsi/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}
