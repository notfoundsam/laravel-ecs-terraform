provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {
    bucket = "project_name-terraform-state"
    key    = "web/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket = "project_name-terraform-state"
    key    = "cluster/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

data "aws_ami" "latest_amazon_linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_route53_zone" "this" {
  name         = "${var.domain}.${var.zone}."
  private_zone = false
}

locals {
  domain                         = "${var.domain}.${var.zone}"
  environment_name               = "production"
  vpc_cidr                       = data.terraform_remote_state.cluster.outputs.cluster_cidr
  vpc_id                         = data.terraform_remote_state.cluster.outputs.cluster_vpc_id
  database_subnet_ids            = data.terraform_remote_state.cluster.outputs.cluster_database_subnet_ids
  alb_dns_name                   = data.terraform_remote_state.cluster.outputs.cluster_alb_dns_name
  alb_zone_id                    = data.terraform_remote_state.cluster.outputs.cluster_alb_zone_id
  alb_listener_arn               = data.terraform_remote_state.cluster.outputs.cluster_alb_listener_arn
  cluster_id                     = data.terraform_remote_state.cluster.outputs.cluster_id
  cluster_name                   = data.terraform_remote_state.cluster.outputs.cluster_name
  cluster_capacity_provider_name = data.terraform_remote_state.cluster.outputs.cluster_capacity_provider_name
  ec2_service_role_arn           = data.terraform_remote_state.cluster.outputs.cluster_ec2_service_role_arn
}

######################################################
#                 Forward requests                   #
######################################################

resource "aws_route53_record" "this" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.domain
  type    = "A"

  alias {
    name                   = local.alb_dns_name
    zone_id                = local.alb_zone_id
    evaluate_target_health = true
  }
}

# Target groups
resource "aws_lb_target_group" "this" {
  name                 = "${var.project_name}-${local.environment_name}-tg"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = local.vpc_id
  deregistration_delay = 10

  health_check {
    timeout             = 3
    interval            = 5
    path                = "/healthcheck"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# ALB listeners
resource "aws_lb_listener_rule" "this" {
  listener_arn = local.alb_listener_arn
  priority     = 99

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    host_header {
      values = [local.domain]
    }
  }
}

######################################################
#                      SSM ENV                       #
######################################################

resource "random_string" "rds_pass" {
  length           = 14
  special          = true
  override_special = "!#$"
}

resource "random_string" "app_key" {
  length           = 43
  special          = true
  override_special = "+/"
}

resource "aws_ssm_parameter" "rds_pass" {
  name      = "/${var.project_name}/${local.environment_name}/rds-pass"
  type      = "SecureString"
  value     = random_string.rds_pass.result
  overwrite = true
}

resource "aws_ssm_parameter" "rds_user" {
  name      = "/${var.project_name}/${local.environment_name}/rds-user"
  type      = "String"
  value     = "root"
  overwrite = true
}

resource "aws_ssm_parameter" "rds_db" {
  name      = "/${var.project_name}/${local.environment_name}/rds-db"
  type      = "String"
  value     = local.environment_name
  overwrite = true
}

resource "aws_ssm_parameter" "rds_host" {
  name      = "/${var.project_name}/${local.environment_name}/rds-host"
  type      = "String"
  value     = aws_db_instance.this.address
  overwrite = true
}

resource "aws_ssm_parameter" "app_url" {
  name      = "/${var.project_name}/${local.environment_name}/app-url"
  type      = "String"
  overwrite = true
  value     = "https://${local.domain}"
}

resource "aws_ssm_parameter" "app_key" {
  name      = "/${var.project_name}/${local.environment_name}/app-key"
  type      = "SecureString"
  value     = "base64:${random_string.app_key.result}="
  overwrite = true
}

resource "aws_ssm_parameter" "mail_from_addr" {
  name      = "/${var.project_name}/${local.environment_name}/mail-from-addr"
  type      = "String"
  value     = "info@${local.domain}"
  overwrite = true
}

resource "aws_ssm_parameter" "mail_from_name" {
  name      = "/${var.project_name}/${local.environment_name}/mail-from-name"
  type      = "String"
  value     = "${var.project_name} team"
  overwrite = true
}

######################################################
#                     DATABASE                       #
######################################################

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-sg"
  subnet_ids = local.database_subnet_ids

  tags = {
    Name = "${var.project_name} DB subnet group"
  }
}

resource "aws_security_group" "rds_sg" {
  name   = "${var.project_name}-rds-sg"
  vpc_id = local.vpc_id
  ingress {
    description = "TLS from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "this" {
  identifier        = "${var.project_name}-${local.environment_name}"
  allocated_storage = 30
  storage_type      = "gp2"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  name              = aws_ssm_parameter.rds_db.value
  username          = aws_ssm_parameter.rds_user.value
  password          = random_string.rds_pass.result
  # parameter_group_name   = "default.mysql8.0"
  db_subnet_group_name   = aws_db_subnet_group.this.id
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  apply_immediately      = true
  deletion_protection    = true
}

######################################################
#                 Tasks definition                   #
######################################################

resource "aws_ecs_task_definition" "initial" {
  family             = "${var.project_name}-app"
  task_role_arn      = aws_iam_role.this.arn
  execution_role_arn = aws_iam_role.this.arn
  container_definitions = templatefile("task-definitions/initial.json.tpl", {
    nginx_image = var.nginx_image
    php_image   = var.php_image
  })
  cpu    = 256
  memory = 128
  # requires_compatibilities = "EC2"

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in ${var.ecs_zones}"
  }

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_ecs_task_definition" "queue" {
  family             = "${var.project_name}-queue"
  task_role_arn      = aws_iam_role.this.arn
  execution_role_arn = aws_iam_role.this.arn
  container_definitions = templatefile("task-definitions/queue.json.tpl", {
    nginx_image = var.nginx_image
  })
  cpu    = 128
  memory = 64
  # requires_compatibilities = "EC2"

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in ${var.ecs_zones}"
  }

  lifecycle {
    ignore_changes = all
  }
}

######################################################
#         Task definition role and policy            #
######################################################

resource "aws_iam_role_policy" "this" {
  name = "${var.project_name}TaskDefinitionPolicy"
  role = aws_iam_role.this.id
  policy = templatefile("policies/task-definition.json.tpl", {
    account_id   = var.account_id
    project_name = var.project_name
  })
}

resource "aws_iam_role" "this" {
  name               = "${var.project_name}TaskDefinitionRole"
  assume_role_policy = file("policies/ecs-task-assume-role.json")
}

######################################################
#            Services with auto scaling              #
######################################################

resource "aws_ecs_service" "this" {
  name            = "${var.project_name}-${local.environment_name}-app"
  cluster         = local.cluster_id
  task_definition = "${aws_ecs_task_definition.initial.family}:${aws_ecs_task_definition.initial.revision}"
  desired_count   = 1
  iam_role        = local.ec2_service_role_arn

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "nginx"
    container_port   = 80
  }

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in ${var.ecs_zones}"
  }

  capacity_provider_strategy {
    capacity_provider = local.cluster_capacity_provider_name
    base              = 0
    weight            = 1
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_appautoscaling_target" "this" {
  max_capacity       = 8
  min_capacity       = 1
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "this" {
  name               = "${aws_ecs_service.this.name}-cpu-scale"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = aws_appautoscaling_target.this.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 75
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

resource "aws_ecs_service" "queue" {
  name            = "${var.project_name}-${local.environment_name}-queue"
  cluster         = local.cluster_id
  task_definition = "${aws_ecs_task_definition.queue.family}:${aws_ecs_task_definition.queue.revision}"
  desired_count   = 1

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in ${var.ecs_zones}"
  }

  capacity_provider_strategy {
    capacity_provider = local.cluster_capacity_provider_name
    base              = 0
    weight            = 1
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_appautoscaling_target" "queue" {
  max_capacity       = 2
  min_capacity       = 1
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.queue.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "queue" {
  name               = "${aws_ecs_service.queue.name}-cpu-scale"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.queue.resource_id
  scalable_dimension = aws_appautoscaling_target.queue.scalable_dimension
  service_namespace  = aws_appautoscaling_target.queue.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 75
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

######################################################
#                  Service losgs                     #
######################################################

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/ecs/${var.project_name}/${local.environment_name}/nginx"
  retention_in_days = 90

  tags = {
    Name = "${var.project_name}-${local.environment_name}-nginx"
  }
}

resource "aws_cloudwatch_log_group" "php_fpm" {
  name              = "/ecs/${var.project_name}/${local.environment_name}/php-fpm"
  retention_in_days = 90

  tags = {
    Name = "${var.project_name}-${local.environment_name}-php-fpm"
  }
}

resource "aws_cloudwatch_log_group" "migrate" {
  name              = "/ecs/${var.project_name}/${local.environment_name}/migrate"
  retention_in_days = 90

  tags = {
    Name = "${var.project_name}-${local.environment_name}-migrate"
  }
}

resource "aws_cloudwatch_log_group" "queue" {
  name              = "/ecs/${var.project_name}/${local.environment_name}/queue"
  retention_in_days = 90

  tags = {
    Name = "${var.project_name}-${local.environment_name}-queue"
  }
}
