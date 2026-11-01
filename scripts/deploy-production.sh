#!/usr/bin/env bash
# 安全发布蛋六日记 API 到生产服务器。
#
# 首次发布会迁移旧 xiaowang-diary-api 的 data 和 .env；后续发布保留
# /opt/danliuriji/data 与 /opt/danliuriji/.env。该脚本不会上传本机的
# server/.env 或 server/data，生产密钥只留在服务器。
#
# 用法：
#   ./scripts/deploy-production.sh
#   ./scripts/deploy-production.sh --yes
# 可通过 DEPLOY_HOST 覆盖目标，例如：
#   DEPLOY_HOST=root@47.94.146.17 ./scripts/deploy-production.sh --yes

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/server"
DEPLOY_HOST="${DEPLOY_HOST:-root@47.94.146.17}"
LEGACY_APP_DIR="/opt/xiaowang-diary-api"
APP_DIR="/opt/danliuriji"
YES=0

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

while (($#)); do
  case "$1" in
    --yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for command in git ssh tar; do
  command -v "$command" >/dev/null || {
    echo "缺少命令：$command" >&2
    exit 1
  }
done

test -f "$SERVER_DIR/docker-compose.production.yml" || {
  echo "找不到生产 Compose 配置：$SERVER_DIR/docker-compose.production.yml" >&2
  exit 1
}

git -C "$ROOT_DIR" diff --quiet || {
  echo "工作区存在未提交改动。请先提交，或明确将它们纳入一次发布。" >&2
  exit 1
}
git -C "$ROOT_DIR" diff --cached --quiet || {
  echo "暂存区存在未提交改动。请先提交后再发布。" >&2
  exit 1
}

COMMIT="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD)"
RELEASE_ID="${COMMIT}-$(date -u +%Y%m%dT%H%M%SZ)"
REMOTE_ARCHIVE="/tmp/danliuriji-${RELEASE_ID}.tgz"

cat <<EOF
即将发布：$COMMIT
目标服务器：$DEPLOY_HOST
生产目录：$APP_DIR

该操作会短暂停止当前日记 API，并执行以下可恢复操作：
  - 备份生产 .env 与 data 到 $APP_DIR/backups/<时间戳>/
  - 首次发布时迁移 $LEGACY_APP_DIR 的 .env 与 data
  - 构建并启动 danliuriji-api，检查容器和 HTTPS 健康接口
EOF

if (( ! YES )); then
  read -r -p "继续发布吗？[y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "已取消。"; exit 0 ;;
  esac
fi

# 先验证 SSH 连接和 Docker 前提，避免在传输后才发现环境不满足。
ssh -o BatchMode=yes -o ConnectTimeout=10 "$DEPLOY_HOST" \
  'docker network inspect chenxu-space_app-network >/dev/null && docker info >/dev/null && (docker compose version >/dev/null 2>&1 || docker-compose version >/dev/null 2>&1)'

printf '上传服务端发布包…\n'
COPYFILE_DISABLE=1 tar -C "$SERVER_DIR" \
  --exclude='./node_modules' \
  --exclude='./.env' \
  --exclude='./data' \
  --exclude='./.DS_Store' \
  -czf - . | ssh -o BatchMode=yes -o ConnectTimeout=10 "$DEPLOY_HOST" \
  "cat > '$REMOTE_ARCHIVE'"

# 不在此 heredoc 内插入本地机密；全部密钥只从服务器既有 .env 读取。
ssh -o BatchMode=yes -o ConnectTimeout=10 "$DEPLOY_HOST" \
  "bash -s -- '$RELEASE_ID' '$REMOTE_ARCHIVE' '$APP_DIR' '$LEGACY_APP_DIR'" <<'REMOTE_SCRIPT'
set -euo pipefail

RELEASE_ID="$1"
ARCHIVE="$2"
APP_DIR="$3"
LEGACY_APP_DIR="$4"
RELEASE_DIR="$APP_DIR/releases/$RELEASE_ID"
DATA_DIR="$APP_DIR/data"
ENV_FILE="$APP_DIR/.env"
BACKUP_DIR="$APP_DIR/backups/$(date -u +%Y%m%dT%H%M%SZ)-$RELEASE_ID"
ACTIVE_CONTAINER=""
ROLLED_BACK=0

rollback() {
  status=$?
  if (( status != 0 )) && [[ -n "$ACTIVE_CONTAINER" ]] && (( ROLLED_BACK == 0 )); then
    echo "发布失败，正在恢复 $ACTIVE_CONTAINER…" >&2
    docker start "$ACTIVE_CONTAINER" >/dev/null 2>&1 || true
    ROLLED_BACK=1
  fi
  rm -f "$ARCHIVE"
  exit "$status"
}
trap rollback EXIT

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "服务器未安装 Docker Compose。" >&2
  exit 1
fi

mkdir -p "$APP_DIR/releases" "$DATA_DIR" "$APP_DIR/backups"
mkdir -p "$BACKUP_DIR"

# 每次发布均备份可变生产状态；发布包本身绝不包含它们。
if [[ -f "$ENV_FILE" ]]; then
  install -m 600 "$ENV_FILE" "$BACKUP_DIR/.env"
fi
if [[ -d "$DATA_DIR" ]]; then
  tar -C "$DATA_DIR" -czf "$BACKUP_DIR/data.tgz" .
fi

# 第一版从旧服务迁移数据与秘密。后续发布始终保留新目录内的状态。
if [[ ! -f "$ENV_FILE" ]] && [[ -f "$LEGACY_APP_DIR/.env" ]]; then
  install -m 600 "$LEGACY_APP_DIR/.env" "$ENV_FILE"
fi
if [[ ! -f "$DATA_DIR/db.json" ]] && [[ -d "$LEGACY_APP_DIR/data" ]]; then
  cp -a "$LEGACY_APP_DIR/data/." "$DATA_DIR/"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "缺少生产环境变量：$ENV_FILE（旧服务中也未找到可迁移的 .env）" >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"
tar -xzf "$ARCHIVE" -C "$RELEASE_DIR"
ln -sfn ../../data "$RELEASE_DIR/data"
ln -sfn ../../.env "$RELEASE_DIR/.env"

"${COMPOSE[@]}" -f "$RELEASE_DIR/docker-compose.production.yml" config -q

# 记住当前健康服务；只有新容器健康后才永久停用它。出错会由 trap 重启。
if docker inspect -f '{{.State.Running}}' danliuriji-api 2>/dev/null | grep -qx true; then
  ACTIVE_CONTAINER="danliuriji-api"
elif docker inspect -f '{{.State.Running}}' xiaowang-diary-api 2>/dev/null | grep -qx true; then
  ACTIVE_CONTAINER="xiaowang-diary-api"
fi
if [[ -n "$ACTIVE_CONTAINER" ]]; then
  echo "停止当前服务：$ACTIVE_CONTAINER"
  docker stop "$ACTIVE_CONTAINER" >/dev/null
fi

echo "构建并启动 danliuriji-api…"
"${COMPOSE[@]}" -f "$RELEASE_DIR/docker-compose.production.yml" up -d --build

for _ in $(seq 1 30); do
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' danliuriji-api 2>/dev/null || true)"
  if [[ "$health" == "healthy" ]]; then
    break
  fi
  if [[ "$health" == "unhealthy" || -z "$health" ]]; then
    echo "新容器未通过健康检查（状态：${health:-missing}）。" >&2
    exit 1
  fi
  sleep 2
done
[[ "$health" == "healthy" ]] || {
  echo "等待新容器健康检查超时（状态：$health）。" >&2
  exit 1
}

# Nginx 通过 Docker DNS 解析 diary-api；reload 使其解析新容器地址。
docker exec chenxu-space-nginx nginx -t
docker exec chenxu-space-nginx nginx -s reload

curl --fail --silent --show-error --max-time 15 \
  --resolve diary-api.peanutwcx.xyz:443:127.0.0.1 \
  https://diary-api.peanutwcx.xyz/api/health
printf '\n发布成功：%s\n备份位置：%s\n' "$RELEASE_ID" "$BACKUP_DIR"
REMOTE_SCRIPT

printf '生产发布完成。\n'
