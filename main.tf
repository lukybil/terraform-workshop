terraform {                     // this is the beginning of a terraform file
  required_providers {          //providers are set
    aws = {                     // we are using AWS
      source  = "hashicorp/aws" // hashicorp/aws is the docker image for the aws provider
      version = "~> 4.16"       //specified verison of the image
    }
  }

  required_version = ">= 1.2.0" // terraform version

  cloud {
    organization = "infc"

    workspaces {
      name = "github-actions"
    }
  }
}

provider "aws" {       // provider set to AWS, here the login takes place
  region = "us-east-1" // specified region
}

resource "aws_vpc" "workshop2" { // VPC
  cidr_block = "10.0.0.0/16"     // How many addresses there are available in the private network (65_536)

  tags = {
    Name = "workshop2"
  }
}

resource "aws_internet_gateway" "workshop2" { // Internet gateway
  vpc_id = aws_vpc.workshop2.id               // only the VPC id is enough

  tags = {
    Name = "workshop2"
  }
}

resource "aws_route_table" "workshop2" { // Route table
  vpc_id = aws_vpc.workshop2.id

  route { // IPv4 internet route, all traffic is routed to the internet
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.workshop2.id
  }

  route { // IPv6 internet route, all traffic is routed to the internet
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.workshop2.id
  }

  tags = {
    Name = "workshop2"
  }
}

resource "aws_subnet" "workshop2_public" { // subnet with 256 IPs available
  vpc_id     = aws_vpc.workshop2.id
  cidr_block = "10.0.1.0/24" // 256 IPs

  tags = {
    Name = "workshop2"
  }
}

// associate the subnet with the route table
// at first I forgot this and the subnet did not have access to the internet
resource "aws_route_table_association" "workshop2" {
  subnet_id      = aws_subnet.workshop2_public.id // id of the subnet
  route_table_id = aws_route_table.workshop2.id   // id of the route table
}

resource "aws_security_group" "workshop2" { //create a security group
  name        = "workshop2"
  description = "Allow TCP inbound traffic on port 80 and SSH on port 22"
  vpc_id      = aws_vpc.workshop2.id

  // ingresses are rules for the incoming traffic
  //22 for SSH connection
  ingress {
    description      = "SSH"
    from_port        = 22 //inside port
    to_port          = 22 // outside port
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] // from anywhere
    ipv6_cidr_blocks = ["::/0"]      // from anywhere IPv6
  }

  // 80 as the default HTTP port, Apache is a HTTP web server
  ingress {
    description      = "Apache web server HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  // allow all outgoing traffic
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  // the Name tag is shown in the AWS console as the name of the resource
  tags = {
    Name = "workshop2"
  }
}

// I have generated RSA keys with ssh-keygen
resource "aws_key_pair" "workshop2" {
  key_name = "workshop2"
  // the public key from the key pair is pasted here
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDMvDOpl6/Rpf6ySB37k1tsix7jFULAGRnVbHYhw8NoewVTgOypiNbwnuU5bQfMaI/N2jAYqulgi7VoBJpvpnzXDFZi5Ce+CCvXMY6QVDyqU17L3K2ksFiUZ5UUEIeNNqI1HCoao0VFITuFX1bo6/+0duozgxURLqtNWoLdkBKAOILatskvbIsIqcp3Dz5tgH4k1LfRzVrWNBOT8aPEc8OPvvFDt7l/KYku3sLDuRymuVQYsXBUuNkqhsIZRSh5X9S3ZNWpXXVDw9yvBLHrKSxVhXKKRozgjU9KDKudj+S+7959//c8PRAIcYmtU6eqi536iTlNsQe1uoHr2sWNtdhO3aQQBd+CLrLZvtAm3gRJDteeP8UUoCHuUNdZg/4+5U2XZg310TBAxqsOu6rCHCT7XR02D5YR1/1XgCGYE2ksGrT0tOXw8R1I8lfW83nBq2FaoKNRXRc/StR4YHOv0KbQ9BqtDBjZBMeBf9cmej+zsZqwuwZKPkOG4eXEBjDaZIM= lukyb@DESKTOP-2C5SOC5"
}

// Create a network interface for the apache_server instance
resource "aws_network_interface" "apache_server" {
  count           = 2
  subnet_id       = aws_subnet.workshop2_public.id
  private_ips     = ["10.0.1.${50 + count.index}"] // set the private IP
  security_groups = [aws_security_group.workshop2.id]
  tags = {
    Name = "apache_server_network_interface"
  }
}

resource "aws_instance" "apache_server" { // "aws_instance" is the resource type and "apache_server" resource name in Terraform
  ami           = "ami-08c40ec9ead489470" // instance ami, found in AWS console when creating a new instance
  instance_type = "t2.micro"              // type of instance, can also be copied from the AWS console

  tags = {                               // tags for the instance
    Name = "ApacheServer-${count.index}" // this sets the name shown in e.g. the AWS console
  }

  count = 2

  network_interface {
    network_interface_id = aws_network_interface.apache_server[count.index].id
    device_index         = 0
  }

  // SSH key reference
  key_name = aws_key_pair.workshop2.key_name

  // security group to allow the SSH and HTTP connections
  // vpc_security_group_ids = [aws_security_group.workshop2.id]

  // user_data is executed on the instance launch, it MUST be properly formatted as we have found out, no tabs or spaces are allowed before the first shebang
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install apache2 -y
              sudo systemctl start apache2
              sudo systemctl enable apache2
              echo "<h1>Hello World</h1>" | sudo tee /var/www/html/index.html
              EOF
}



// elastic IP is the public IP address
resource "aws_eip" "apache_server" {
  count    = 2
  vpc      = true // the EIP is in a VPC so true
  instance = aws_instance.apache_server[count.index].id
  // just in case, it would throw an error if EIP would be created before the internet gateway
  // since without it, there is no connection to the internet and thus the public address does not make sense
  depends_on = [
    aws_internet_gateway.workshop2
  ]

  tags = {
    Name = "apache_server_eip_${count.index}"
  }
}

// load balancer
resource "aws_lb" "workshop2" {
  name               = "workshop2"
  load_balancer_type = "network"                        // does balancing on the network level
  internal           = false                            // is facing the internet
  subnets            = [aws_subnet.workshop2_public.id] // is in one subnet

  tags = {
    Name = "workshop2"
  }
}

// creates a target group to be later used as the instances the load balancer routes to
// there are no instances added yet though, this happens in the next step
resource "aws_lb_target_group" "workshop2" {
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.workshop2.id
  depends_on = [
    aws_lb.workshop2 // would fail if created before the load balancer
  ]
}

// target group attachment for attaching the instances to the target group
resource "aws_lb_target_group_attachment" "workshop2" {
  count            = 2
  target_group_arn = aws_lb_target_group.workshop2.arn
  target_id        = aws_instance.apache_server[count.index].id
  port             = 80

}

// create a load balancer listener, it is an event and the action which is to be taken
// this resource connects the load balancer to the target group
resource "aws_lb_listener" "workshop2" {
  load_balancer_arn = aws_lb.workshop2.arn
  // the event is if there is an incoming TCP connection on port 80 
  port     = "80"
  protocol = "TCP"

  // the action is to forward it on the target group
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.workshop2.arn
  }
}

// output the public ip address of the launched instance
output "ec2_global_ips" {
  value = ["${aws_instance.apache_server.*.public_ip}"]
}

// output the DNS of the load balancer
output "lb_ip" {
  value = ["${aws_lb.workshop2.dns_name}"]
}
