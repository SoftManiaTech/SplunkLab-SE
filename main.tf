terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}

resource "aws_security_group" "splunk_sg" {
  name        = "splunk-security-group"
  description = "Security group for Splunk server"

  ingress { 
    from_port = 22
    to_port = 22 
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
    }

    ingress { 
    from_port = 8000 
    to_port = 8000 
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
    }

    ingress { 
    from_port = 8089 
    to_port = 8089 
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
    }

   egress { 
    from_port = 0 
    to_port = 0 
    protocol = "-1" 
    cidr_blocks = ["0.0.0.0/0"] 
    }
}

resource "aws_instance" "splunk_server" {
  ami                  = lookup(var.ami_map, var.region, "")
  instance_type        = var.instance_type
  key_name             = var.key_name
  vpc_security_group_ids = [aws_security_group.splunk_sg.id]
  associate_public_ip_address = var.elastic_ip_needed

  root_block_device {
    volume_size = var.storage_size
  }

  tags = {
    Name = var.instance_name
    AutoStop = true
    Owner = var.usermail
    UserEmail = var.usermail
    RunQuotaHours = var.quotahours
    Category = var.category
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.key_name}.pem")
      host        = self.public_ip
    }

    inline = [
      "echo '${var.ssh_public_key}' >> ~/.ssh/authorized_keys"
    ]
  }
}

resource "aws_eip" "splunk_eip" {
  count    = var.elastic_ip_needed ? 1 : 0
  instance = aws_instance.splunk_server.id
  vpc      = true
}

resource "local_file" "ansible_inventory" {
  filename = "inventory.ini"

  content = <<EOF
[splunk]
${var.instance_name} ansible_host=${var.elastic_ip_needed ? aws_eip.splunk_eip[0].public_ip : aws_instance.splunk_server.public_ip} ansible_user=ec2-user
EOF
}

resource "local_file" "ansible_group_vars" {
  filename = "group_vars/all.yml"

  content = <<EOF
---
splunk_instance:
  name: ${var.instance_name}
  private_ip: ${aws_instance.splunk_server.private_ip}
  instance_id: ${aws_instance.splunk_server.id}
  splunk_admin_password: admin123
EOF
}
