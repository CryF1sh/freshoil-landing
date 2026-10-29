#!/usr/bin/env bash
# Включает отправку заявок с сайта на почту (через SMTP Gmail).
# Использование: sudo bash deploy/setup-mail.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="/etc/freshoil-mailer.env"

if [[ $EUID -ne 0 ]]; then
  echo "Запустите через sudo"; exit 1
fi
source /etc/freshoil.conf   # DOMAIN=..., записывается при setup.sh

echo "==> 1/4 Настройки почты"
if [[ -f "$ENV_FILE" ]]; then
  echo "    $ENV_FILE уже есть — оставляю как есть (чтобы поменять, удалите файл и запустите скрипт снова)"
else
  read -rp "    Gmail, с которого отправлять и на который получать заявки: " MAIL
  read -rsp "    Пароль приложения Gmail (16 букв, ввод не отображается): " PASS; echo
  umask 077
  cat > "$ENV_FILE" <<CONF
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USER=${MAIL}
SMTP_PASSWORD=${PASS// /}
MAIL_TO=${MAIL}
MAIL_FROM=${MAIL}
CONF
  chmod 600 "$ENV_FILE"
fi

echo "==> 2/4 Проверяю отправку (тестовое письмо)"
if ! (set -a; source "$ENV_FILE"; set +a; python3 "$REPO_DIR/deploy/mailer/mailer.py" --test); then
  echo "✗ Письмо не отправилось. Проверьте пароль приложения: sudo nano $ENV_FILE"
  echo "  Затем запустите скрипт ещё раз."
  exit 1
fi

echo "==> 3/4 Запускаю службу freshoil-mailer"
sed "s|__REPO_DIR__|${REPO_DIR}|" "$REPO_DIR/deploy/mailer/freshoil-mailer.service" \
  > /etc/systemd/system/freshoil-mailer.service
systemctl daemon-reload
systemctl enable --now freshoil-mailer >/dev/null
systemctl restart freshoil-mailer
sleep 1
systemctl is-active --quiet freshoil-mailer || { journalctl -u freshoil-mailer -n 20 --no-pager; exit 1; }

echo "==> 4/4 Подключаю /api/order в nginx"
bash "$REPO_DIR/deploy/install-snippets.sh" "$DOMAIN"

echo
echo "✓ Готово! Заявки с https://${DOMAIN} будут приходить на $(grep ^MAIL_TO "$ENV_FILE" | cut -d= -f2)"
echo "  Логи службы:     sudo journalctl -u freshoil-mailer -f"
echo "  Копия заявок:    sudo cat /var/lib/freshoil/orders.jsonl"
