data "aws_ami" "latest_amazon_ecs" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# Create AWS role if does not exist
# resource "aws_iam_service_linked_role" "ecs" {
#   aws_service_name = "ecs.amazonaws.com"
# }

######################################################
#                  EC2InstanceRole                   #
######################################################

resource "aws_iam_role" "ecs_ec2_role" {
  name               = "${var.project_name}EcsInstanceRole"
  path               = "/${var.project_name}/"
  assume_role_policy = file("policies/ec2-assume-role.json")
}

resource "aws_iam_instance_profile" "ecs_ec2_role" {
  name = "${var.project_name}EcsInstanceProfile"
  role = aws_iam_role.ecs_ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_role" {
  role       = aws_iam_role.ecs_ec2_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

######################################################
#                   ECSServiceRole                   #
######################################################

resource "aws_iam_role" "ec2_service_role" {
  name               = "${var.project_name}InstanceServiceRole"
  path               = "/${var.project_name}/"
  assume_role_policy = file("policies/ecs-assume-role.json")
}

resource "aws_iam_role_policy_attachment" "ec2_service_role" {
  role       = aws_iam_role.ec2_service_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

######################################################
#                  EC2 Autoscaling                   #
######################################################

resource "aws_security_group" "lc" {
  name   = "${var.project_name}-lc-sg"
  vpc_id = module.cluster_vpc.vpc_id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-lc-sg"
  }
}

resource "aws_launch_configuration" "main" {
  name_prefix                 = "${var.project_name}-lc-"
  image_id                    = data.aws_ami.latest_amazon_ecs.id
  instance_type               = "t3.micro"
  associate_public_ip_address = true
  enable_monitoring           = false
  security_groups             = [aws_security_group.lc.id]
  iam_instance_profile        = aws_iam_instance_profile.ecs_ec2_role.id
  user_data = templatefile("shell/user_data.sh.tpl", {
    cluster_name = "${var.project_name}-main"
  })

  root_block_device {
    volume_type = "gp2"
    volume_size = 30
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "main" {
  name                  = "${var.project_name}-asg"
  launch_configuration  = aws_launch_configuration.main.name
  vpc_zone_identifier   = module.cluster_vpc.public_subnet_ids
  min_size              = 0
  max_size              = 1
  desired_capacity      = 1
  default_cooldown      = 30
  health_check_type     = "EC2"
  protect_from_scale_in = true
  termination_policies  = ["Default"]

  tag {
    key                 = "AmazonECSManaged"
    value               = "yes"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes        = [desired_capacity, min_size, max_size]
    create_before_destroy = true
  }
  depends_on = [aws_lb.main]
}

######################################################
#                      Cluster                       #
######################################################

resource "aws_ecs_capacity_provider" "main" {
  name = aws_launch_configuration.main.name

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.main.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 100
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
  lifecycle {
    ignore_changes = [name]
  }
  depends_on = [aws_lb.main]
}

resource "aws_ecs_cluster" "main" {
  name               = "${var.project_name}-main"
  capacity_providers = [aws_ecs_capacity_provider.main.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.main.name
    weight            = 1
  }

  depends_on = [aws_lb.main]
}

######################################################
#             Fargate security groups                #
######################################################

resource "aws_security_group" "migrate" {
  name   = "${var.project_name}-migrate-sg"
  vpc_id = module.cluster_vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-migrate-sg"
  }
}
