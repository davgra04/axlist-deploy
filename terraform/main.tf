# Specify the provider and access details
provider "aws" {
  region = "us-west-2"
}

resource "aws_key_pair" "auth" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

####################################################################################################
##  INFRA (vpc, internet gateway, route table, subnet)
####################################################################################################

# Create a VPC to launch our instances into
resource "aws_vpc" "axlist-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
      Name = "axlist-VPC"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "axlist-ig" {
  vpc_id = aws_vpc.axlist-vpc.id
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.axlist-vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.axlist-ig.id
}

# Create a subnet to launch our instances into
resource "aws_subnet" "axlist-subnet" {
  vpc_id                  = aws_vpc.axlist-vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-2a"
}

####################################################################################################
##  SECURITY GROUPS
####################################################################################################

# The default security group to grant outbound Internet access and SSH from a
# single IP
resource "aws_security_group" "axlist-default-sg" {
  name        = "axlist-default-sg"
  description = "Default security group for axlist"
  vpc_id      = aws_vpc.axlist-vpc.id

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
resource "aws_security_group" "axlist-http-sg" {
  name        = "axlist-http-sg"
  description = "HTTP(S) security group for axlist"
  vpc_id      = aws_vpc.axlist-vpc.id

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

# Security group which grants 8080 access for testing
resource "aws_security_group" "axlist-testhttp-sg" {
  name        = "axlist-testhttp-sg"
  description = "HTTP(S) security group for axlist"
  vpc_id      = aws_vpc.axlist-vpc.id

  # HTTP access from my IP
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }
}

# Security group which grants DB admin access to my IP
resource "aws_security_group" "axlist-db-sg" {
  name        = "axlist-db-sg"
  description = "DB security group for axlist"
  vpc_id      = aws_vpc.axlist-vpc.id

  # DB access from my IP
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }
}

# Security group which grants access between all instances
resource "aws_security_group" "axlist-internal-sg" {
  name        = "axlist-internal-sg"
  description = "Internal security group for axlist"
  vpc_id      = aws_vpc.axlist-vpc.id

  # DB access from my IP
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    security_groups = [aws_security_group.axlist-default-sg.id]
  }
}


####################################################################################################
##  EC2
####################################################################################################

# nginx load balancer instance
resource "aws_instance" "axlist-lb" {
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
  subnet_id = aws_subnet.axlist-subnet.id

  vpc_security_group_ids = [
    aws_security_group.axlist-default-sg.id,
    aws_security_group.axlist-internal-sg.id,
    aws_security_group.axlist-http-sg.id,
  ]

  tags = {
    Name = "axlist-lb",
    Project = "axlist"
  }
}

# elastic IP association for axlist-lb
resource "aws_eip_association" "eip_assoc" {
  # instance_id   = aws_instance.axlist-lb.id
  instance_id   = aws_instance.axlist-lb.id
  allocation_id = var.eip_allocation_id
}

# db instance
resource "aws_instance" "axlist-db" {
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
  subnet_id = aws_subnet.axlist-subnet.id

  vpc_security_group_ids = [
    aws_security_group.axlist-default-sg.id,
    aws_security_group.axlist-internal-sg.id,
    aws_security_group.axlist-db-sg.id,
  ]

  tags = {
    Name = "axlist-db",
    Project = "axlist"
  }
}

# axlist app instance
resource "aws_instance" "axlist-app" {
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
  subnet_id = aws_subnet.axlist-subnet.id

  vpc_security_group_ids = [
    aws_security_group.axlist-default-sg.id,
    aws_security_group.axlist-internal-sg.id,
    aws_security_group.axlist-testhttp-sg.id,
  ]

  tags = {
    Name = "axlist-app",
    Project = "axlist"
  }
}
