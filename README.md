# **Docker-Kanboard**

Dockerfile for Kanboard using PHP with NGINX Unit application server.

## **Usage**

The Compose file assumes that you have build the Docker image as follows:
```console
docker build -t kanboard --build-arg PHP_VERSION=7.4.7 --build-arg NGINX_UNIT_VERSION=1.18.0 --build-arg KANBOARD_VERSION=v1.2.15 .
```
Check the `entrypoint.sh` script to see what environment variables can be used.

## **License**

Licensed under MIT License (See the LICENSE file).

## **Author**

[Saad Ali](https://github.com/nixknight)
