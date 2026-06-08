#!/bin/bash

# Confirm container IP
docker inspect hapi-r4 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{.NetworkID}}{{end}}'

# check iptables nat table for the container
sudo iptables -t nat -L DOCKER -n -v | grep -A2 -B2 "4004\|8080"

# check if docker-proxy is running for this port
ps aux | grep docker-proxy | grep 4004

# Try curling the container IP directly on 8080 (which bypasses all port mappings)
CONTAINER_IP=$(docker inspect hapi-r4 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo "Container IP: $CONTAINER_IP"
curl -s http://${CONTAINER_IP}:8080/fhir/metadata | head -5


