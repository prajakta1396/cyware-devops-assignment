provider "aws" {
  region = "ap-south-1"
}

#Create VPC#
resource "aws_vpc" "Test-vpc" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "Test-vpc"
  }
}

#Create public subnet#
resource "aws_subnet" "Test-public" {
  vpc_id = aws_vpc.Test-vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone = "ap-south-1a"

  tags = {
    "Name" = "Test-public-1"
  }
}

#Create Internet gateway#
resource "aws_internet_gateway" "test-gw" {
  vpc_id = aws_vpc.Test-vpc.id

  tags = {
    Name = "Test-vpc"
  }
}

#Create private subnet#
resource "aws_subnet" "Test-private" {
  vpc_id = aws_vpc.Test-vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    "Name" = "Test-private-1"
  }
}

#Create elastic ip#
resource "aws_eip" "Tets-elastic-ip" {
}

#Creat NAT gateway#
resource "aws_nat_gateway" "Test_nat_gateway" {
  allocation_id = aws_eip.Tets-elastic-ip.id
  subnet_id = aws_subnet.Test-private.id
}


#Create route table for internet gateway#
resource "aws_route_table" "test-public-route" {
  vpc_id = aws_vpc.Test-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test-gw.id
  }
  tags = {
    "Name" = "Test-public-1"
  }
}

resource "aws_route_table_association" "Test-public-1" {
  subnet_id      = aws_subnet.Test-public.id
  route_table_id = aws_route_table.test-public-route.id
}

#Creat route table for NAT gateway#
resource "aws_route_table" "test-private-route" {
  vpc_id = aws_vpc.Test-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    network_interface_id = aws_nat_gateway.Test_nat_gateway.id
    #nat_gateway_id = aws_nat_gateway.Test_nat_gateway.id
  }
}
resource "aws_route_table_association" "Test-private-1" {
  subnet_id      = aws_subnet.Test-private.id
  route_table_id = aws_route_table.test-private-route.id
}

#Create Security group#
resource "aws_security_group" "test-security-grp" {
  vpc_id = aws_vpc.Test-vpc.id
  name = "ec2-private-sg"
  ingress {
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 22
    to_port = 22
  }
  ingress {
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 80
    to_port = 80
  }
  
  egress {
    protocol = -1
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
  }
}

output "aws_security_gr_id" {
  value = "${aws_security_group.test-security-grp.id}"
}

#Create EC2 instances in private subnets#
resource "aws_instance" "test-private-inst-1" {
  ami = "ami-07d3a50bd29811cd1"
  instance_type = "t2.micro"
  vpc_security_group_ids = ["${aws_security_group.test-security-grp.id}"]
  subnet_id = "${aws_subnet.Test-private.id}"
  key_name = "demo"
  count = 2

  user_data = <<-EOF

  #!/bin/bash
  sudo yum update -y
  sudo yum install httpd -y
  sudo systemctl start httpd
  sudo systemctl enable httpd
  echo "<html><h1> Hello World!! </h1></html>"

  EOF
  tags = {
    Name = "test-private-inst-1"
  }
}
resource "aws_lb" "Test-alb" {
  name = "Test-lb"
  load_balancer_type = "application"
  subnets = [aws_subnet.Test-private.id]
  security_groups = [aws_security_group.test-security-grp.id]
  tags = {
    Name = "Test-lb"
  }
}


resource "aws_lb_target_group" "Test-lbt" {
health_check {
  interval = 20
  path = "/"
  protocol = "HTTP"
  healthy_threshold = 5
}

  name_prefix = "Testlb"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.Test-vpc.id
}

resource "aws_lb_listener" "Test-alb-listener"{
  load_balancer_arn = aws_lb.Test-alb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.Test-lbt.arn
    type = "forward"
  }
}

resource "aws_lb_target_group_attachment" "ec2-attach" {
  count = length(aws_instance.test-private-inst-1)
  target_group_arn = aws_lb_target_group.Test-lbt.arn
  target_id = aws_instance.test-private-inst-1[count.index].id
}