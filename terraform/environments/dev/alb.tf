# Self-signed TLS cert for the ALB's HTTPS listener.

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "demo" {
  private_key_pem = tls_private_key.demo.private_key_pem

  subject {
    common_name  = "advisor-chat.demo.internal"
    organization = "AI Gateway PoC"
  }

  validity_period_hours = 24 * 30
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "aws_acm_certificate" "demo" {
  private_key      = tls_private_key.demo.private_key_pem
  certificate_body = tls_self_signed_cert.demo.cert_pem
}
