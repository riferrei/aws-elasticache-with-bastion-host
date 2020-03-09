###########################################
################### AWS ###################
###########################################

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region = var.aws_region
}

###########################################
################ Networking ###############
###########################################

resource "aws_vpc" "aws_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "${var.global_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.aws_vpc.id
  tags = {
    Name = "${var.global_prefix}-internet-gateway"
  }
}

resource "aws_route" "main_route" {
  route_table_id = aws_vpc.aws_vpc.main_route_table_id
  gateway_id = aws_internet_gateway.internet_gateway.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.aws_vpc.id
  tags = {
    Name = "${var.global_prefix}-private-route-table"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "cache_server" {
  vpc_id = aws_vpc.aws_vpc.id
  count = length(data.aws_availability_zones.available.names)
  cidr_block = element(var.private_cidr_blocks, count.index)
  map_public_ip_on_launch = false
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "${var.global_prefix}-cache-server-${count.index}"
  }
}

resource "aws_subnet" "bastion_host" {
  vpc_id = aws_vpc.aws_vpc.id
  cidr_block = "10.0.10.0/24"
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "${var.global_prefix}-bastion-host"
  }
}

resource "aws_route_table_association" "cache_server_association" {
  count = length(data.aws_availability_zones.available.names)
  subnet_id = element(aws_subnet.cache_server.*.id, count.index)
  route_table_id = aws_route_table.private_route_table.id
}

###########################################
############# Security Groups #############
###########################################

resource "aws_security_group" "cache_server" {
  name = "${var.global_prefix}-cache-server"
  description = "AWS ElastiCache for Redis"
  vpc_id = aws_vpc.aws_vpc.id
  ingress {
    from_port = 6379
    to_port = 6379
    protocol = "tcp"
    security_groups = [aws_security_group.bastion_host.id]
  }
  ingress {
    from_port = 6379
    to_port = 6379
    protocol = "tcp"
    cidr_blocks = var.private_cidr_blocks
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.global_prefix}-cache-server"
  }
}

resource "aws_security_group" "bastion_host" {
  name = "${var.global_prefix}-bastion-host"
  description = "Cache Server Bastion Host"
  vpc_id = aws_vpc.aws_vpc.id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.global_prefix}-bastion-host"
  }
}

###########################################
########## ElastiCache for Redis ##########
###########################################

resource "aws_elasticache_subnet_group" "cache_server" {
  name = "${var.global_prefix}-cache-server"
  subnet_ids = aws_subnet.cache_server[*].id
  description = "${var.global_prefix}-cache-server"
}

resource "aws_elasticache_replication_group" "cache_server" {
  replication_group_id = "${var.global_prefix}-cache-server"
  replication_group_description = "AWS ElastiCache for Redis"
  subnet_group_name = aws_elasticache_subnet_group.cache_server.name
  availability_zones = data.aws_availability_zones.available.names
  number_cache_clusters = length(data.aws_availability_zones.available.names)
  security_group_ids = [aws_security_group.cache_server.id]
  automatic_failover_enabled = true
  node_type = "cache.m4.large"
  parameter_group_name = "default.redis5.0"
  port = 6379
}

###########################################
############## Bastion Host ###############
###########################################

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "private_key" {
  key_name = var.global_prefix
  public_key = tls_private_key.private_key.public_key_openssh
}

resource "local_file" "private_key" {
  content  = tls_private_key.private_key.private_key_pem
  filename = "cert.pem"
}

resource "null_resource" "private_key_permissions" {
  depends_on = [local_file.private_key]
  provisioner "local-exec" {
    command = "chmod 600 cert.pem"
    interpreter = ["bash", "-c"]
    on_failure  = continue
  }
}

data "aws_ami" "amazon_linux_2" {
 most_recent = true
 owners = ["amazon"]
 filter {
   name = "owner-alias"
   values = ["amazon"]
 }
 filter {
   name = "name"
   values = ["amzn2-ami-hvm*"]
 }
}

data "template_file" "bastion_host" {
  template = file("bastion-host.sh")
  vars = {
    cache_server = aws_elasticache_replication_group.cache_server.primary_endpoint_address
  }
}

resource "aws_instance" "bastion_host" {
  depends_on = [aws_elasticache_replication_group.cache_server]
  ami = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  key_name = aws_key_pair.private_key.key_name
  subnet_id = aws_subnet.bastion_host.id
  vpc_security_group_ids = [aws_security_group.bastion_host.id]
  user_data = data.template_file.bastion_host.rendered
  root_block_device {
    volume_type = "gp2"
    volume_size = 100
  }
  tags = {
    Name = "${var.global_prefix}-bastion-host"
  }
}
