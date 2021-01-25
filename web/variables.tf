variable "project_name" {
  default = "project_name-web"
}

variable "region" {
  default = "ap-northeast-1"
}

variable "domain" {
  default = "project_name"
}

variable "zone" {
  default = "com"
}

variable "account_id" {
  default = "aws_account_id"
}

variable "nginx_image" {
  default = "nginx:1.13.5-alpine"
}

variable "php_image" {
  default = "php:7.3.11-fpm-alpine3.10"
}

variable "ecs_zones" {
  default = "[ap-northeast-1a, ap-northeast-1c]"
}
