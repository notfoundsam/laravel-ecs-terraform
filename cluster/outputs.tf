output "cluster_vpc_id" {
  value = module.cluster_vpc.vpc_id
}

output "cluster_cidr" {
  value = module.cluster_vpc.vpc_cidr
}

output "cluster_public_subnet_ids" {
  value = module.cluster_vpc.public_subnet_ids
}

output "cluster_private_subnet_ids" {
  value = module.cluster_vpc.private_subnet_ids
}

output "cluster_database_subnet_ids" {
  value = module.cluster_vpc.database_subnet_ids
}

output "cluster_alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "cluster_alb_zone_id" {
  value = aws_lb.main.zone_id
}

output "cluster_id" {
  value = aws_ecs_cluster.main.id
}
output "cluster_name" {
  value = aws_ecs_cluster.main.name
}
output "cluster_capacity_provider_name" {
  value = aws_ecs_capacity_provider.main.name
}

output "cluster_alb_arn" {
  value = aws_lb.main.arn
}

output "cluster_alb_listener_arn" {
  value = aws_lb_listener.https.arn
}

output "cluster_ec2_service_role_arn" {
  value = aws_iam_role.ec2_service_role.arn
}

output "cluster_migration_sg_id" {
  value = aws_security_group.migrate.id
}
