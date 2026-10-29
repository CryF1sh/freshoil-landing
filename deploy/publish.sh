#!/usr/bin/env bash
# Копирует файлы сайта из репозитория в папку, которую отдаёт nginx.
# Использование: sudo bash deploy/publish.sh example.by
set -euo pipefail

DOMAIN="${1:?Укажите домен: sudo bash deploy/publish.sh example.by}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEBROOT="/var/www/${DOMAIN}"

mkdir -p "$WEBROOT"
rsync -a --delete \
  --exclude '.git' --exclude 'deploy' --exclude 'README.md' --exclude '.gitignore' \
  "$REPO_DIR"/ "$WEBROOT"/

LASTMOD="$(git -C "$REPO_DIR" log -1 --format=%cs 2>/dev/null || date +%F)"
sed -i -e "s/__DOMAIN__/${DOMAIN}/g" -e "s/__LASTMOD__/${LASTMOD}/g" \
  "$WEBROOT/robots.txt" "$WEBROOT/sitemap.xml" "$WEBROOT/llms.txt"

chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} +
find "$WEBROOT" -type f -exec chmod 644 {} +

echo "✓ Файлы сайта опубликованы в $WEBROOT"
