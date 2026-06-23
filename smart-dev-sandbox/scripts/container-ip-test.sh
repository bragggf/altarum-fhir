#!/bin/bash

CONTAINER_NAME=hapi-r4
PORT=4013

CONTAINER_IP=$(docker inspect ${CONTAINER_NAME}  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo "Container IP: $CONTAINER_IP"
curl -v http://${CONTAINER_IP}:${PORT}/fhir/metadata 2>&1 | head -20


