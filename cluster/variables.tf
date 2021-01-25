variable "project_name" {
  default = "project_name"
}

variable "region" {
  default = "ap-northeast-1"
}

variable "vpc_cidr" {
  default = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  default = [
    "10.1.1.0/24",
    "10.1.2.0/24"
  ]
}

variable "private_subnet_cidrs" {
  # default = [
  #   "10.1.11.0/24",
  #   "10.1.12.0/24"
  # ]
  default = []
}

variable "database_subnet_cidrs" {
  default = [
    "10.1.21.0/24",
    "10.1.22.0/24",
  ]
}

variable "public_ip" {
  default = true
}

variable "white_list_ip" {
  default = [
    "192.168.100.100/32"
  ]
}

variable "ssh_key_name" {
  default = "project_key"
}
