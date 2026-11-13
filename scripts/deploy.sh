#!/bin/bash
# Roda na EC2. Uso: bash -s -- <imagem-completa-com-tag> <sha-do-commit>
set -euo pipefail

IMAGE_URI="${1:?informe a imagem completa com tag}"
COMMIT_SHA="${2:?informe o sha do commit}"
REGION="us-east-1"
CONTAINER_NAME="devops-api"
REGISTRY="${IMAGE_URI%%/*}"

echo "==> Login no ECR usando a IAM Role da instancia"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Baixando a imagem do commit ${COMMIT_SHA}"
docker pull "$IMAGE_URI"

echo "==> Removendo o container antigo (se existir)"
docker rm -f "$CONTAINER_NAME" || true

echo "==> Iniciando o container novo"
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p 80:8000 \
  -e APP_COMMIT="$COMMIT_SHA" \
  "$IMAGE_URI"

echo "==> Verificando a saude da aplicacao"
for attempt in $(seq 1 20); do
  if curl --fail --silent http://127.0.0.1/health; then
    echo
    echo "==> Aplicacao saudavel (tentativa ${attempt})"
    docker ps --filter "name=${CONTAINER_NAME}"
    curl --silent http://127.0.0.1/version
    echo
    exit 0
  fi
  echo "Tentativa ${attempt}: aplicacao ainda nao esta pronta"
  sleep 2
done

echo "ERRO: a aplicacao nao respondeu em /health"
docker logs "$CONTAINER_NAME"
exit 1