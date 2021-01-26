## About project

Infrastructure for Laravel framework on AWS ECS
See related project on [GitHub](https://github.com/notfoundsam/laravel-ecs-web)

### Preparation

- Terraform v0.14.x
- AWS account
- Domain name (possible to create in AWS $12 per year)

### Creating a cluster

1. Create an AWS user with programmatic access and policy AdministratorAccess for terrafom. Keep it in a safe place.
2. Create an s3 where terrafom will save its states. Enable encryption. Enable Bucket Versioning if it's necessary.
3. By a domain name on AWS or another place and set up it in Route53.
4. Create certificates `your_domain.zone` and `*.your_domain.zone` with Certificate Manager for region you will use. Validate them with route53 records.
5. In `./cluster/variables.tf` set up `project_name`, `region`, `ssh_key_name` and other if it's necessary.
6. In `./cluster/main.tf` update `project_name` and `region` for `backend s3` from step 2. Also replace `AWS_ACCOUNT_ID` and `CERTIFICATE_ID` for the Load Balancer from step 4.
7. If you need a bastion server change count to 1 in `./cluster/main.tf` at the aws_instance bastion settings.
8. If you have never created ECS claster before uncomment `aws_iam_service_linked_role` block in `./cluster/ecs.tf`
9. Export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from step 1 to the shell where you planing to run terraform.
10. Change the directory to `cd cluster` and run `terraform init`.
11. Run `terraform plan` to check is everything ok and run `terraform apply` to create the cluster.

### Creating services

1. In `./web/main.tf` update `project_name`, `region`, `domain`, `zone`, `account_id` and `ecs_zones` to yours.
2. In `./web/production.tf` update `project_name` and `region` for `backend s3` and `terraform_remote_state` from step 2 of Creating a cluster.
3. Change the directory to `cd web` and run `terraform init`.
4. Run `terraform plan` to check is everything ok and run `terraform apply` to create services.
