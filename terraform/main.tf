# Specify the provider and access details
provider "aws" {
  region = "us-west-2"
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

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "auxcord-sg" {
  name        = "auxcord-sg"
  description = "Main security group for auxcord"
  vpc_id      = aws_vpc.auxcord-vpc.id

  # SSH access from my IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  # HTTP access from my IP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    # cidr_blocks = [var.my_ip]
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from my IP
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    # cidr_blocks = [var.my_ip]
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


####################################################################################################
##  EC2
####################################################################################################

resource "aws_key_pair" "auth" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

resource "aws_instance" "auxcord-web" {

  connection {
    # type        = "ssh"
    user        = "centos"
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }

  root_block_device {
    volume_size = 64
  }

  instance_type = var.dgserv_instance_type

  ami = lookup(var.aws_amis, var.aws_region)

  key_name = aws_key_pair.auth.id

  vpc_security_group_ids = [aws_security_group.auxcord-sg.id]

  subnet_id = aws_subnet.auxcord-subnet.id

  tags = {
    Name = "auxcord"
  }
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.auxcord-web.id
  allocation_id = var.eip_allocation_id
}
