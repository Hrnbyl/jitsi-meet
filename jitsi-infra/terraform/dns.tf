# Create the Route 53 Hosted Zone for your new domain
resource "aws_route53_zone" "primary" {
  name = "hrnbyl.com"

  tags = {
    Environment = "Production"
    Project     = "Jitsi-Meet"
  }
}

# Request the ACM SSL Certificate for meet.hrnbyl.com
resource "aws_acm_certificate" "jitsi_cert" {
  domain_name       = "meet.hrnbyl.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Create the DNS Validation Records in Route 53
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.jitsi_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.primary.zone_id
}

# Validate the certificate automatically
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.jitsi_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Output the nameservers to update in BigRock
output "route53_nameservers" {
  value       = aws_route53_zone.primary.name_servers
  description = "Nameservers to update in your BigRock dashboard"
}
