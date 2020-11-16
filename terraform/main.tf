# Specify the provider and access details
provider "aws" {
  region = "us-west-2"
}

resource "aws_key_pair" "auth" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

####################################################################################################
##  INFRA (vpc, internet gateway, route table, subnet, security group)
####################################################################################################

# Create a VPC to launch our instances into
resource "aws_vpc" "auxcord-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
      Name = "auxcord-VPC"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "auxcord-ig" {
  vpc_id = aws_vpc.auxcord-vpc.id
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.auxcord-vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.auxcord-ig.id
}

# Create a subnet to launch our instances into
resource "aws_subnet" "auxcord-subnet" {
  vpc_id                  = aws_vpc.auxcord-vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-2a"
}

# The default security group to grant outbound Internet access and SSH from a
# single IP
resource "aws_security_group" "auxcord-default-sg" {
  name        = "auxcord-default-sg"
  description = "Default security group for auxcord"
  vpc_id      = aws_vpc.auxcord-vpc.id

  # SSH access from my IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group which grants HTTP(S) access
resource "aws_security_group" "auxcord-http-sg" {
  name        = "auxcord-http-sg"
  description = "HTTP(S) security group for auxcord"
  vpc_id      = aws_vpc.auxcord-vpc.id

  # HTTP access from my IP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from my IP
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


####################################################################################################
##  EC2
####################################################################################################

# nginx load balancer instance
resource "aws_instance" "auxcord-lb" {
  connection {
    # type        = "ssh"
    user        = "centos"
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }

  root_block_device {
    volume_size = 32
  }

  instance_type = var.instance_type_lb
  ami = lookup(var.aws_amis, var.aws_region)
  key_name = aws_key_pair.auth.id
  subnet_id = aws_subnet.auxcord-subnet.id

  vpc_security_group_ids = [
    aws_security_group.auxcord-default-sg.id,
    aws_security_group.auxcord-http-sg.id,
  ]

  tags = {
    Name = "auxcord-lb",
    Project = "auxcord"
  }
}

# elastic IP association for auxcord-lb
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.auxcord-lb.id
  allocation_id = var.eip_allocation_id
}

# db instance
resource "aws_instance" "auxcord-db" {
  connection {
    # type        = "ssh"
    user        = "centos"
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }

  root_block_device {
    volume_size = 32
  }

  instance_type = var.instance_type_db
  ami = lookup(var.aws_amis, var.aws_region)
  key_name = aws_key_pair.auth.id
  subnet_id = aws_subnet.auxcord-subnet.id

  vpc_security_group_ids = [
    aws_security_group.auxcord-default-sg.id,
  ]

  tags = {
    Name = "auxcord-db",
    Project = "auxcord"
  }
}

# auxcord app instance
resource "aws_instance" "auxcord-app" {
  connection {
    # type        = "ssh"
    user        = "centos"
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }

  root_block_device {
    volume_size = 32
  }

  instance_type = var.instance_type_app
  ami = lookup(var.aws_amis, var.aws_region)
  key_name = aws_key_pair.auth.id
  subnet_id = aws_subnet.auxcord-subnet.id

  vpc_security_group_ids = [
    aws_security_group.auxcord-default-sg.id,
  ]

  tags = {
    Name = "auxcord-app",
    Project = "auxcord"
  }
}
