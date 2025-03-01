provider "aws" {
  region = "eu-west-1"
}

# Creating VPC
resource "aws_vpc" "deji_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "deji_vpc"
  }
}

# Creating public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.deji_vpc.id
  cidr_block              = "10.0.5.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-1b"
  tags = {
    Name = "public-subnet"
  }
}

# Creating private subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.deji_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-west-1c"
  tags = {
    Name = "hng_private-subnet"
  }
}

# Creating internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.deji_vpc.id
  tags = {
    Name = "hng_internet-gateway"
  }
}

# Creating public routing table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.deji_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "hng_publicRBT"
  }
}

# Creating routing table association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Creating security group for the test server
resource "aws_security_group" "todo_sg" {
  vpc_id = aws_vpc.deji_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
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
    Name = "todo_sg"
  }
}

# Generating keypair
data "aws_key_pair" "existing_key" {
  key_name = "deji_new"
}

resource "aws_key_pair" "deji_new" {
  count      = length(data.aws_key_pair.existing_key.id) == 0 ? 1 : 0
  key_name   = "deji_new"
  public_key = file("~/.ssh/deji_new.pub")
}

# EC2 Instance
resource "aws_instance" "todo-app" {
  ami             = "ami-03fd334507439f4d1"
  instance_type   = "t2.large"
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.todo_sg.id]
  key_name        = length(aws_key_pair.deji_new) > 0 ? aws_key_pair.deji_new[0].id : null
  tags = {
    Name = "todo-app"
  }
}

# Associate the existing EIP with the EC2 instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.todo-app.id
  allocation_id = "eipalloc-077ac577e8bf24286"  
}

# Output the Elastic IP directly
output "instance_ip" {
  value       = "54.246.122.204"  
  description = "The public IP of the EC2 instance"
}

# Create Ansible variables file with the IP address
resource "local_file" "ansible_vars" {
  content = <<-EOF
---
terraform_output:
  elastic_ip: "54.246.122.204" 
EOF
  filename = "../${path.module}/ansible/terraform_vars.yml"
}

# Wait for EC2 instance to be ready
resource "null_resource" "wait_for_instance" {
  depends_on = [
    aws_instance.todo-app,
    aws_eip_association.eip_assoc
  ]

  # Use remote-exec to wait for SSH to be available (This will block until SSH is ready)
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/deji_new")
      host        = "54.246.122.204"
      timeout     = "5m"
    }
    
    # Just a minimal command to test SSH access
    inline = ["echo 'Instance is ready!'"]
  }
}

# Run Ansible after instance is confirmed ready
# resource "null_resource" "run_ansible" {
#   depends_on = [
#     null_resource.wait_for_instance,
#     local_file.ansible_vars
#   ]
  
#    provisioner "local-exec" {
#     command = "ssh-keygen -R 54.246.122.204 && sleep 120 && ansible-playbook -i ansible/inventory.yaml --extra-vars '@ansible/terraform_vars.yml' ansible/playbook.yaml"
#   }
# }