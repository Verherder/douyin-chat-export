#!/usr/bin/env bash
set -eu

cd "$(dirname "$0")"

DOUYIN_PORT="${DOUYIN_CHAT_PORT:-8000}"
DOUYIN_HOST="${DOUYIN_CHAT_HOST:-127.0.0.1}"
DOUYIN_URL="http://${DOUYIN_HOST}:${DOUYIN_PORT}"
SPACE_PYTHON="${DOUYIN_CHAT_PYTHON:-/Users/jiaming/miniforge3/envs/space/bin/python}"
OPEN_BROWSER="${DOUYIN_CHAT_OPEN_BROWSER:-1}"
SKIP_BUILD="${DOUYIN_CHAT_SKIP_BUILD:-0}"
OPENER_PID=""

cleanup() {
  if [ -n "$OPENER_PID" ]; then
    kill "$OPENER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if [ ! -x "$SPACE_PYTHON" ]; then
  printf '错误：找不到 space 环境的 Python：%s\n' "$SPACE_PYTHON" >&2
  printf '可通过 DOUYIN_CHAT_PYTHON 指定正确路径。\n' >&2
  exit 1
fi

if ! "$SPACE_PYTHON" -c 'import fastapi, uvicorn, playwright' 2>/dev/null; then
  printf '错误：space 环境缺少 fastapi、uvicorn 或 playwright。\n' >&2
  printf '请先在 space 环境安装 requirements.txt 中的依赖。\n' >&2
  exit 1
fi

if [ "$SKIP_BUILD" != "1" ]; then
  if [ -d frontend/node_modules ]; then
    printf '正在构建前端...\n'
    (cd frontend && npm run build)
  elif [ ! -f frontend/dist/index.html ]; then
    printf '错误：前端尚未安装或构建。请先运行：\n' >&2
    printf '  cd frontend && npm install && npm run build\n' >&2
    exit 1
  else
    printf '未找到 frontend/node_modules，使用已有的 frontend/dist。\n'
  fi
fi

if curl --silent --fail --output /dev/null "$DOUYIN_URL"; then
  printf '服务已在运行：%s\n' "$DOUYIN_URL"
  if [ "$OPEN_BROWSER" = "1" ]; then
    open "$DOUYIN_URL"
  fi
  exit 0
fi

if [ "$OPEN_BROWSER" = "1" ]; then
  # 服务就绪后再打开浏览器，避免启动期间出现连接失败页面。
  (
    for _ in $(seq 1 60); do
      if curl --silent --fail --output /dev/null "$DOUYIN_URL"; then
        open "$DOUYIN_URL"
        exit 0
      fi
      sleep 1
    done
    printf '服务启动超时，请检查终端输出：%s\n' "$DOUYIN_URL" >&2
  ) &
  OPENER_PID=$!
fi

printf '使用 space 环境启动抖音聊天记录工具：%s\n' "$DOUYIN_URL"
printf '按 Control-C 停止服务。\n\n'

"$SPACE_PYTHON" -m uvicorn backend.main:app \
  --host "$DOUYIN_HOST" \
  --port "$DOUYIN_PORT"
