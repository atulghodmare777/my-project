provider "aws" {
  region = "ap-south-1"
}

variable "cidr" {
  default = "10.0.0.0/16"
}

/*resource "aws_key_pair" "example" {
  key_name = "mumbai-linux"
  public_key = file("${path.module}/mumbai-linux.pem")
}*/

resource "aws_vpc" "myvpc" {
  cidr_block = var.cidr
}

resource "aws_subnet" "sub1" {
  vpc_id = aws_vpc.myvpc.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
}

resource "aws_route_table" "RT" {
  vpc_id = aws_vpc.myvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta1" {
  subnet_id = aws_subnet.sub1.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_security_group" "websg" {
  name = "web"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    description = "HTTP from vpc"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "web-sg"
  }
}

resource "aws_instance" "server" {
  ami = "ami-001843b876406202a"
  instance_type = "t2.micro"
  key_name = "mumbai-linux"
  vpc_security_group_ids = [aws_security_group.websg.id]
  subnet_id = aws_subnet.sub1.id
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = file("${path.module}/mumbai-linux.pem")
    host = self.public_ip
  }
  provisioner "file" {
    source = "app.py"
    destination = "/home/ec2-user/app.py"
  }
  provisioner "remote-exec" {
    inline = [ 
      "echo 'hello from ec2-instance'",
      "sudo yum install update -y",
      "sudo yum install python3-pip -y ",
      "cd /home/ec2-user",
      "sudo pip3 install flask",
      "sudo python3 app.py &"
     ]
  }
}
