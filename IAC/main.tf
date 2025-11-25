provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "epicbook-rishav-02"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "my_bucket_website" {
  bucket = aws_s3_bucket.my_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "my_bucket_block" {
  bucket = aws_s3_bucket.my_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "read_only_access_policy" {
  statement {
    sid    = "AllowPublicRead"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.my_bucket.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "my_bucket_policy" {
  bucket = aws_s3_bucket.my_bucket.id
  policy = data.aws_iam_policy_document.read_only_access_policy.json
}

resource "null_resource" "sync_s3_folder" {
  provisioner "local-exec" {
    command = "aws s3 sync /home/rishav/Ebook s3://${aws_s3_bucket.my_bucket.id}/"
  }

  depends_on = [
    aws_s3_bucket.my_bucket,
    aws_s3_bucket_policy.my_bucket_policy,
    aws_s3_bucket_website_configuration.my_bucket_website,
  ]
}


data "aws_route53_zone" "main" {
  name         = "rishavops.online"
  private_zone = false
}

resource "aws_acm_certificate" "rishavops_certificate" {
  domain_name       = "rishavops.online"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "rishavops_validation" {
  for_each = {
    for dvo in aws_acm_certificate.rishavops_certificate.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.main.id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "rishavops_certificate_validation" {
  certificate_arn         = aws_acm_certificate.rishavops_certificate.arn
  validation_record_fqdns = [for rec in aws_route53_record.rishavops_validation : rec.fqdn]

  timeouts {
    create = "60m"
  }
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.my_bucket.bucket_domain_name
    origin_id   = "S3-my-bucket-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN for S3 static website"
  default_root_object = "index.html"

  aliases = ["rishavops.online"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-my-bucket-origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.rishavops_certificate.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "S3StaticWebsiteCDN"
  }
}


