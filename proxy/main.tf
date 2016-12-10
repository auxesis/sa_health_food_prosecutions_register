# VPC
provider "aws" {
	access_key = "${var.aws_access_key}"
	secret_key = "${var.aws_secret_key}"
	region = "us-east-1"
}

resource "aws_vpc" "proxy" {
	cidr_block = "10.1.0.0/16"

	tags {
		Name = "sa_health_food_prosecutions_register"
	}
}

resource "aws_internet_gateway" "proxy" {
	vpc_id = "${aws_vpc.proxy.id}"
}

# Public subnets
resource "aws_subnet" "us-east-1b-public" {
	vpc_id = "${aws_vpc.proxy.id}"

	cidr_block = "10.1.0.0/24"
	availability_zone = "us-east-1b"
	tags {
		Name = "sa_health_food_prosecutions_register"
	}
}

# Routing table for public subnets
resource "aws_route_table" "us-east-1-public" {
	vpc_id = "${aws_vpc.proxy.id}"

	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = "${aws_internet_gateway.proxy.id}"
	}

	tags {
		Name = "sa_health_food_prosecutions_register"
	}
}

resource "aws_route_table_association" "us-east-1b-public" {
	subnet_id = "${aws_subnet.us-east-1b-public.id}"
	route_table_id = "${aws_route_table.us-east-1-public.id}"
}

# morph access to elb
resource "aws_security_group" "elb" {
	name = "elb"
	description = "Access for ELB clients"
	vpc_id = "${aws_vpc.proxy.id}"

	# Inbound proxy requests
	ingress {
		from_port = 8888
		to_port = 8888
		protocol = "tcp"
		cidr_blocks = ["50.116.3.88/32"]
	}

	# Outbound internet access
	egress {
		from_port   = 0
		to_port     = 0
		protocol    = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags {
		Name = "sa_health_food_prosecutions_register_elb"
	}
}


resource "aws_security_group" "proxy" {
	name = "proxy"
	description = "Access for proxy instances"
	vpc_id = "${aws_vpc.proxy.id}"

	# SSH access
	ingress {
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	# ELB health checks
	ingress {
		from_port   = 0
		to_port     = 0
		protocol    = "-1"
		cidr_blocks	= ["10.1.0.0/16"]
	}

	# Outbound internet access
	egress {
		from_port   = 0
		to_port     = 0
		protocol    = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags {
		Name = "sa_health_food_prosecutions_register_ssh"
	}
}

resource "aws_elb" "proxy-elb" {
	name = "sa-health-proxy-elb"

	subnets  = [ "${aws_subnet.us-east-1b-public.id}" ]
	security_groups = [ "${aws_security_group.elb.id}" ]

	listener {
		instance_port     = 8888
		instance_protocol = "tcp"
		lb_port           = 8888
		lb_protocol       = "tcp"
	}

	health_check {
		healthy_threshold   = 2
		unhealthy_threshold = 2
		timeout             = 3
		target              = "TCP:8888"
		interval            = 60
	}
}

resource "aws_key_pair" "proxy-kp" {
	key_name = "proxy-kp"
	public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCBDR/3WUDKHgE6lVGyNuDn0/XOeHUc1sfkIDCuzl8wXZwrkBrk2tZnRuRgeVYIDvHwRyAAbWDC2yakSsJqzI995Jfc0VU2mdV0sZVqpEH/ijdQ/ykZlqU+91y3dvL+iFEh/4kd0Tw87MKYwkUC0KYI7uFoxDDhDIsE20aVlnYB/JCHLr/xpSbpok0G+dcGdIOWQdiSLKC9OacTWrOLCgq7z9i1QUiu4VBaItO2lJxQSQo/4pWtXWW82+CXLApVQN7tfZavpr7yrralAg0oNciK6ZAYIVdvc0UltvaynhBYP44xK3nCaQXCrqE4Q7mNEjMZI7B8hb14Z18J9lE/L0F3"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_launch_configuration" "proxy-lc" {
  name_prefix = "sa_health_food_prosecutions_register_proxy-"
	image_id = "${data.aws_ami.ubuntu.id}"
  instance_type = "t2.micro"
	associate_public_ip_address = true
	key_name = "proxy-kp"
	security_groups = [ "${aws_security_group.proxy.id}" ]
	user_data = "${file("userdata.sh")}"

	lifecycle {
		create_before_destroy = true
	}
}

resource "aws_autoscaling_group" "proxy-asg" {
	name = "sa_health_food_prosecutions_register_proxy-asg"
	availability_zones = [ "us-east-1b" ]
	min_size = 1
	max_size = 1
	health_check_type = "EC2"

	launch_configuration = "${aws_launch_configuration.proxy-lc.name}"
	vpc_zone_identifier  = [ "${aws_subnet.us-east-1b-public.id}" ]
	load_balancers       = ["${aws_elb.proxy-elb.name}"]

	lifecycle {
		create_before_destroy = true
	}

	tag {
		key   = "Name"
		value = "sa_health_food_prosecutions_register"
		propagate_at_launch = true
	}
}
