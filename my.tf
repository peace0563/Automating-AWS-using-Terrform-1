provider "aws" {
  profile = "peace0563"
  region  = "ap-south-1"
}

resource "tls_private_key" "gen-key" {
  algorithm   = "RSA"
  provisioner "local-exec" {
        command = "echo '${tls_private_key.gen-key.private_key_pem}' > keyy-1.pem && chmod 400 keyy-1.pem"
    }
}

resource "aws_key_pair" "mykeypair" {

  depends_on = [
    tls_private_key.gen-key,
  ]

  key_name   = "keyy-1"
  public_key = tls_private_key.gen-key.public_key_openssh
}

resource "aws_security_group" "allow_ssh_https_http" {


  name        = "security"
  description = "allows http https ssh"
  vpc_id = "vpc-00051968"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

   ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

resource "aws_s3_bucket" "image_buck" {

  bucket = "temp32145"
  force_destroy = true
  acl    = "public-read"

  tags = {
    Name        = "buck_img"
  }
}

locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_s3_bucket_object" "object" {

  depends_on = [
    aws_s3_bucket.image_buck,
  ]

  bucket = "temp32145"
  key    = "image.png"
  source = "C:/Users/Kaushlesh Maurya/Pictures/sample-page.png"
  etag = "${filemd5("C:/Users/Kaushlesh Maurya/Pictures/sample-page.png")}"
  acl = "public-read"
}



resource "aws_cloudfront_distribution" "s3_distribution" {

    depends_on = [
    aws_s3_bucket_object.object
  ]

  origin {
    domain_name = aws_s3_bucket.image_buck.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.image_buck.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "image.png"

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.image_buck.bucket_domain_name
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.image_buck.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = aws_s3_bucket.image_buck.id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.image_buck.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_instance" "web" {

  depends_on = [
    aws_key_pair.mykeypair,
    aws_security_group.allow_ssh_https_http,
  ]

  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "keyy-1"
  security_groups = [ "security" ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.gen-key.private_key_pem
    host     = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "mywebserver"
  }
}


resource "aws_ebs_volume" "esb1" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  tags = {
    Name = "webserver-ebs"
  }
}


resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.esb1.id}"
  instance_id = "${aws_instance.web.id}"
  force_detach = true
}


resource "null_resource" "nullremote3"  {

depends_on = [
    aws_volume_attachment.ebs_att,
    aws_cloudfront_distribution.s3_distribution,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.gen-key.private_key_pem
    host     = aws_instance.web.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/peace0563/Devops_Task_2.git /var/www/html/",
      "sudo sed -i 's,image_url,https://${aws_cloudfront_distribution.s3_distribution.domain_name}/image.png,g' /var/www/html/index.html",
      "sudo systemctl restart httpd"
    ]
  }
}


output "myos_ip" {
  value = aws_instance.web.public_ip
}




