#!/bin/bash

CONTAINER_IP=$(docker inspect hapi-r4 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo "Container IP: $CONTAINER_IP"
curl -v http://${CONTAINER_IP}:8080/fhir/metadata 2>&1 | head -20


