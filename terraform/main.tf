provider "aws" {
  region = "us-east-1"
}

# 1. Generate an SSH key pair locally
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2. Register the public key in AWS (so it shows up in the console)
resource "aws_key_pair" "generated_key" {
  key_name   = "terraform-generated-key"
  public_key = tls_private_key.example.public_key_openssh
}

# 3. Lookup the default VPC
data "aws_vpc" "default" {
  default = true
}

# 4. Security group allowing SSH (22) and HTTP (80)
resource "aws_security_group" "allow_ssh_http" {
  name        = "allow_ssh_http"
  description = "Allow SSH and HTTP access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 5. EC2 instance with cloud‑init
resource "aws_instance" "web" {
  ami                    = "ami-0c02fb55956c7d316"  # Ubuntu 22.04 LTS in us-east-1
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]
  depends_on             = [aws_key_pair.generated_key]

  # cloud-init to inject SSH key and install Docker
  user_data = <<-EOF
    #cloud-config
    ssh_authorized_keys:
      - ${tls_private_key.example.public_key_openssh}

    package_update: true
    packages:
      - docker.io

    runcmd:
      - usermod -aG docker ubuntu
      - systemctl enable docker
      - systemctl start docker
  EOF

  tags = {
    Name = "terraform-ec2-docker"
  }
}

# 6. Persist the private key locally for SSH access
resource "local_file" "private_key_pem" {
  content         = tls_private_key.example.private_key_pem
  filename        = "${path.module}/terraform-generated-key.pem"
  file_permission = "0400"
}

# 7. Output the EC2 public IP
output "instance_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP of the EC2 instance"
}
