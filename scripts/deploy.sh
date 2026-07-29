#!/usr/bin/env bash

set -euo pipefail

CONTAINER_NAME="nginx-cicd-demo"
HEALTH_URL="http://127.0.0.1:8080/health"

PROJECT_DIR=$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)

cd "$PROJECT_DIR"

NEW_IMAGE="${1:-}"

if [[ -z "$NEW_IMAGE" ]]; then
  echo "用法: $0 <image-ref>"
  exit 2
fi

if ! docker image inspect "$NEW_IMAGE" > /dev/null 2>&1; then
  echo "错误：本地不存在镜像 $NEW_IMAGE"
  exit 2
fi

PREVIOUS_IMAGE=$(
  docker inspect \
    --format '{{.Config.Image}}' \
    "$CONTAINER_NAME" \
    2> /dev/null ||
  true
)

container_health() {
  docker inspect \
    --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
    "$CONTAINER_NAME" \
    2> /dev/null ||
  echo "missing"
}

wait_for_health() {
  local attempt
  local status

  for attempt in $(seq 1 12); do
    status=$(container_health)

    echo "健康检查 $attempt/12：$status"

    if [[ "$status" == "healthy" ]] &&
       curl -fsS "$HEALTH_URL" > /dev/null; then
      return 0
    fi

    if [[ "$status" == "unhealthy" ||
          "$status" == "exited" ||
          "$status" == "dead" ||
          "$status" == "missing" ]]; then
      return 1
    fi

    sleep 5
  done

  return 1
}

deploy_image() {
  local image_ref="$1"

  echo "部署镜像：$image_ref"

  IMAGE_REF="$image_ref" \
    docker compose up \
      -d \
      --force-recreate \
      --no-build
}

rollback() {
  if [[ -z "$PREVIOUS_IMAGE" ]]; then
    echo "没有可回滚的旧镜像"
    return 1
  fi

  if [[ "$PREVIOUS_IMAGE" == "$NEW_IMAGE" ]]; then
    echo "新旧镜像相同，无法回滚"
    return 1
  fi

  echo "开始回滚：$PREVIOUS_IMAGE"

  if ! deploy_image "$PREVIOUS_IMAGE"; then
    echo "回滚部署命令失败"
    return 1
  fi

  if wait_for_health; then
    echo "回滚成功：$PREVIOUS_IMAGE"
    return 0
  fi

  echo "回滚后的容器仍不健康"
  return 1
}

echo "当前镜像：${PREVIOUS_IMAGE:-无}"
echo "目标镜像：$NEW_IMAGE"

if ! deploy_image "$NEW_IMAGE"; then
  echo "新版本启动失败"
  rollback || true
  exit 1
fi

if wait_for_health; then
  echo "部署成功：$NEW_IMAGE"
  exit 0
fi

echo "新版本健康检查失败"

docker logs \
  --since 5m \
  "$CONTAINER_NAME" ||
true

rollback || true
exit 1
