# Request the ACM SSL Certificate for meet.hrnbyl.com
resource "aws_acm_certificate" "jitsi_cert" {
  domain_name       = "meet.hrnbyl.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Output the ACM Certificate ARN to put into your Helm values.yaml
output "acm_certificate_arn" {
  value       = aws_acm_certificate.jitsi_cert.arn
  description = "The ARN of the ACM certificate for Helm values.yaml"
}

# Output the CNAME validation record details to manually add to Cloudflare (if not yet validated)
output "domain_validation_options" {
  value       = aws_acm_certificate.jitsi_cert.domain_validation_options
  description = "Add these CNAME records to Cloudflare to validate ACM"
}
