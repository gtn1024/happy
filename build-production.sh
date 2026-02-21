#!/bin/bash
set -e

# Build production Docker image for happy-server
# Uses external PostgreSQL and Redis

IMAGE_NAME="crpi-s5kq75kvbv0rkkxc.cn-hangzhou.personal.cr.aliyuncs.com/gtn1024/happy-server"
TAG="${1:-latest}"

echo "Building production image: ${IMAGE_NAME}:${TAG}"

# Build from project root
docker build -t "${IMAGE_NAME}:${TAG}" -f Dockerfile .

echo "Build complete!"
echo ""
echo "To push to registry:"
echo "  docker push ${IMAGE_NAME}:${TAG}"
echo ""
echo "To run locally:"
echo "  docker-compose up -d"