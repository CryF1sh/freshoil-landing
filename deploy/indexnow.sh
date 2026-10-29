#!/usr/bin/env bash
# Сообщает Яндексу и Bing (а через Bing — ChatGPT, Copilot, DuckDuckGo), что сайт обновился.
# Протокол IndexNow: https://www.indexnow.org. Ключ — файл <ключ>.txt в корне сайта.
# Использование: bash deploy/indexnow.sh example.by
set -uo pipefail

DOMAIN="${1:?Укажите домен}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEY_FILE="$(ls "$REPO_DIR" | grep -E '^[0-9a-f]{32}\.txt$' | head -n1)"
[[ -z "$KEY_FILE" ]] && { echo "Нет файла ключа IndexNow"; exit 0; }
KEY="${KEY_FILE%.txt}"

for url in "https://${DOMAIN}/" "https://${DOMAIN}/llms.txt"; do
  for engine in "https://yandex.com/indexnow" "https://api.indexnow.org/indexnow"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
      "${engine}?url=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$url")&key=${KEY}")
    echo "    IndexNow ${engine#https://} ← ${url}: HTTP ${code}"
  done
done
echo "    (200 или 202 — принято)"
