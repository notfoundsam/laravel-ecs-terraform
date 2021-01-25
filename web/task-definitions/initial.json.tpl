[
  {
    "portMappings": [
      {
        "hostPort": 0,
        "protocol": "tcp",
        "containerPort": 80
      }
    ],
    "cpu": 0,
    "image": "${nginx_image}",
    "essential": true,
    "links": [
      "php-fpm"
    ],
    "name": "nginx"
  },
  {
    "cpu": 0,
    "image": "${php_image}",
    "essential": true,
    "name": "php-fpm"
  }
]
