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

