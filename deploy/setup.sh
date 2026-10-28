#!/usr/bin/env bash
# Первичная установка лендинга FreshOil на Ubuntu + nginx + HTTPS (Let's Encrypt).
# Использование: sudo bash deploy/setup.sh example.by you@mail.com
set -euo pipefail

DOMAIN="${1:?Укажите домен. Пример: sudo bash deploy/setup.sh example.by you@mail.com}"
EMAIL="${2:?Укажите email для SSL-сертификата. Пример: sudo bash deploy/setup.sh example.by you@mail.com}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEBROOT="/var/www/${DOMAIN}"
CONF="/etc/nginx/sites-available/${DOMAIN}"

if [[ $EUID -ne 0 ]]; then
  echo "Запустите через sudo"; exit 1
fi

echo "==> 1/5 Устанавливаю пакеты (nginx, certbot, rsync)"
apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx rsync dnsutils >/dev/null

echo "==> 2/5 Проверяю DNS"
SERVER_IP="$(curl -4 -fsS https://ifconfig.me || true)"
DOMAIN_IP="$(dig +short A "$DOMAIN" | tail -n1)"
WWW_IP="$(dig +short A "www.$DOMAIN" | tail -n1)"
echo "    IP сервера:        ${SERVER_IP:-не определён}"
echo "    $DOMAIN →     ${DOMAIN_IP:-нет записи}"
echo "    www.$DOMAIN → ${WWW_IP:-нет записи}"
if [[ -z "$DOMAIN_IP" ]]; then
  echo "✗ У домена нет A-записи. Добавьте её у регистратора и повторите через 10–30 минут."; exit 1
fi
if [[ -n "$SERVER_IP" && "$DOMAIN_IP" != "$SERVER_IP" ]]; then
  echo "⚠ A-запись домена указывает не на этот сервер. Сертификат может не выпуститься."
fi

echo "==> 3/5 Публикую файлы сайта в $WEBROOT"
bash "$REPO_DIR/deploy/publish.sh" "$DOMAIN"
echo "DOMAIN=${DOMAIN}" > /etc/freshoil.conf

echo "==> 4/5 Настраиваю nginx"
NAMES="$DOMAIN www.$DOMAIN"
[[ -z "$WWW_IP" ]] && NAMES="$DOMAIN"
sed -e "s|server_name __DOMAIN__ www.__DOMAIN__;|server_name ${NAMES};|" \
    -e "s|__WEBROOT__|${WEBROOT}|" \
    "$REPO_DIR/deploy/nginx-freshoil.conf" > "$CONF"
ln -sf "$CONF" "/etc/nginx/sites-enabled/${DOMAIN}"
nginx -t
systemctl reload nginx

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 'Nginx Full' >/dev/null && echo "    ufw: открыты порты 80 и 443"
fi

echo "==> 5/5 Получаю HTTPS-сертификат"
CERT_ARGS=(-d "$DOMAIN")
[[ -n "$WWW_IP" ]] && CERT_ARGS+=(-d "www.$DOMAIN")
certbot --nginx "${CERT_ARGS[@]}" -m "$EMAIL" --agree-tos -n --redirect

echo
echo "✓ Готово! Сайт доступен: https://$DOMAIN"
echo "  Обновление сайта после изменений в GitHub: sudo bash $REPO_DIR/deploy/update.sh"
