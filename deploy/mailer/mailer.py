#!/usr/bin/env python3
"""FreshOil: приём заявок с сайта и отправка их на почту.

Слушает 127.0.0.1:8085, nginx проксирует сюда POST /api/order.
Настройки берутся из переменных окружения (файл /etc/freshoil-mailer.env).
Только стандартная библиотека Python — ничего ставить не нужно.
"""
from __future__ import annotations  # совместимость с Python 3.8 (Ubuntu 20.04)

import html
import json
import os
import re
import smtplib
import ssl
import sys
import threading
import time
from datetime import datetime, timezone, timedelta
from email.message import EmailMessage
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "465"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "").replace(" ", "")
MAIL_TO = os.environ.get("MAIL_TO", SMTP_USER)
MAIL_FROM = os.environ.get("MAIL_FROM", SMTP_USER)
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8085"))
DRY_RUN = os.environ.get("DRY_RUN") == "1"  # для отладки: письмо печатается в лог, а не отправляется
ORDERS_LOG = os.path.join(os.environ.get("STATE_DIRECTORY", "/var/lib/freshoil"), "orders.jsonl")

KITS = {"n4": ("FreshOil 4", 55), "n18": ("FreshOil 18", 199)}
MINSK = timezone(timedelta(hours=3))
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")

# Не больше 5 заявок с одного IP за 10 минут
RATE_LIMIT, RATE_WINDOW = 5, 600
_hits: dict[str, list[float]] = {}
_lock = threading.Lock()


def rate_limited(ip: str) -> bool:
    now = time.time()
    with _lock:
        hits = [t for t in _hits.get(ip, []) if now - t < RATE_WINDOW]
        limited = len(hits) >= RATE_LIMIT
        if not limited:
            hits.append(now)
        _hits[ip] = hits
        return limited


def clean(value, limit: int) -> str:
    return str(value or "").strip()[:limit]


def validate(data: dict) -> tuple[dict | None, str | None]:
    order = {
        "name": clean(data.get("name"), 100),
        "phone": clean(data.get("phone"), 40),
        "email": clean(data.get("email"), 120),
        "comment": clean(data.get("comment"), 2000),
        "sample": bool(data.get("sample")),
    }
    for key in KITS:
        try:
            order[key] = max(0, min(999, int(data.get(key) or 0)))
        except (TypeError, ValueError):
            return None, "Некорректное количество наборов."
    if not order["name"]:
        return None, "Укажите имя."
    if len(re.findall(r"\d", order["phone"])) < 9:
        return None, "Укажите корректный телефон."
    if not EMAIL_RE.match(order["email"]):
        return None, "Укажите корректный email."
    if not (order["n4"] or order["n18"] or order["sample"]):
        return None, "Выберите хотя бы один набор или бесплатный образец."
    return order, None


def build_email(order: dict, ip: str) -> EmailMessage:
    rows = [(name, order[key], price) for key, (name, price) in KITS.items() if order[key]]
    total = sum(qty * price for _, qty, price in rows)
    if order["sample"]:
        rows.append(("Бесплатный образец", 1, 0))
    when = datetime.now(MINSK).strftime("%d.%m.%Y %H:%M")

    text_lines = [
        f"Новая заявка с сайта FreshOil ({when})",
        "",
        f"Имя:      {order['name']}",
        f"Телефон:  {order['phone']}",
        f"Email:    {order['email']}",
        "",
        *[f"{name} × {qty} = {qty * price} BYN" for name, qty, price in rows],
        "",
        f"ИТОГО: {total} BYN",
    ]
    if order["comment"]:
        text_lines += ["", "Комментарий:", order["comment"]]

    e = html.escape
    item_rows = "".join(
        f"<tr><td style='padding:8px 12px;border-top:1px solid #e1eae1'>{e(name)}</td>"
        f"<td style='padding:8px 12px;border-top:1px solid #e1eae1;text-align:center'>{qty}</td>"
        f"<td style='padding:8px 12px;border-top:1px solid #e1eae1;text-align:right'>{price} BYN</td>"
        f"<td style='padding:8px 12px;border-top:1px solid #e1eae1;text-align:right'><b>{qty * price} BYN</b></td></tr>"
        for name, qty, price in rows
    )
    comment_html = (
        f"<h3 style='color:#1B5E20;margin:24px 0 8px'>Комментарий</h3>"
        f"<div style='background:#F4F8F4;border-radius:8px;padding:12px 14px;white-space:pre-wrap'>{e(order['comment'])}</div>"
        if order["comment"] else ""
    )
    html_body = f"""\
<div style="font-family:Arial,sans-serif;color:#333;max-width:600px">
  <h2 style="color:#1B5E20;margin:0 0 4px">Новая заявка FreshOil</h2>
  <div style="color:#5b645b;font-size:13px;margin-bottom:20px">{when}</div>
  <table style="border-collapse:collapse;font-size:15px;margin-bottom:20px">
    <tr><td style="padding:4px 16px 4px 0;color:#5b645b">Имя</td><td><b>{e(order['name'])}</b></td></tr>
    <tr><td style="padding:4px 16px 4px 0;color:#5b645b">Телефон</td><td><a href="tel:{e(re.sub(r'[^0-9+]', '', order['phone']))}">{e(order['phone'])}</a></td></tr>
    <tr><td style="padding:4px 16px 4px 0;color:#5b645b">Email</td><td><a href="mailto:{e(order['email'])}">{e(order['email'])}</a></td></tr>
  </table>
  <table style="border-collapse:collapse;width:100%;font-size:14px;border:1px solid #e1eae1">
    <tr style="background:#2E7D32;color:#fff">
      <th style="padding:8px 12px;text-align:left">Набор</th><th style="padding:8px 12px">Кол-во</th>
      <th style="padding:8px 12px;text-align:right">Цена</th><th style="padding:8px 12px;text-align:right">Сумма</th>
    </tr>
    {item_rows}
    <tr style="background:#F4F8F4"><td colspan="3" style="padding:10px 12px;text-align:right"><b>Итого</b></td>
      <td style="padding:10px 12px;text-align:right;color:#1B5E20;font-size:17px"><b>{total} BYN</b></td></tr>
  </table>
  {comment_html}
  <p style="color:#999;font-size:12px;margin-top:24px">Чтобы ответить клиенту, просто нажмите «Ответить» — письмо уйдёт на его адрес. IP: {e(ip)}</p>
</div>"""

    msg = EmailMessage()
    msg["Subject"] = f"Заявка FreshOil: {order['name']} — {total} BYN".replace("\n", " ")
    msg["From"] = f"Сайт FreshOil <{MAIL_FROM}>"
    msg["To"] = MAIL_TO
    msg["Reply-To"] = order["email"]
    msg.set_content("\n".join(text_lines))
    msg.add_alternative(html_body, subtype="html")
    return msg


def send_email(msg: EmailMessage) -> None:
    if DRY_RUN:
        print("---- DRY_RUN email ----\n" + msg.get_body(("plain",)).get_content(), flush=True)
        return
    context = ssl.create_default_context()
    if SMTP_PORT == 465:
        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context, timeout=20) as s:
            s.login(SMTP_USER, SMTP_PASSWORD)
            s.send_message(msg)
    else:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20) as s:
            s.starttls(context=context)
            s.login(SMTP_USER, SMTP_PASSWORD)
            s.send_message(msg)


def save_order(order: dict, ip: str, sent: bool) -> None:
    """Резервная копия каждой заявки — на случай, если почта не дошла."""
    try:
        os.makedirs(os.path.dirname(ORDERS_LOG), exist_ok=True)
        record = {"time": datetime.now(MINSK).isoformat(timespec="seconds"), "ip": ip, "sent": sent, **order}
        with open(ORDERS_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError as err:
        print(f"Не удалось сохранить заявку в {ORDERS_LOG}: {err}", file=sys.stderr, flush=True)


class Handler(BaseHTTPRequestHandler):
    def reply(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path.rstrip("/") != "/api/order":
            return self.reply(404, {"ok": False, "error": "Not found"})
        ip = self.headers.get("X-Real-IP") or self.client_address[0]
        length = int(self.headers.get("Content-Length") or 0)
        if not 0 < length <= 10_000:
            return self.reply(413, {"ok": False, "error": "Слишком большой запрос."})
        try:
            data = json.loads(self.rfile.read(length))
            assert isinstance(data, dict)
        except (ValueError, AssertionError):
            return self.reply(400, {"ok": False, "error": "Некорректный запрос."})

        if data.get("website"):  # скрытое поле-ловушка: его заполняют только боты
            return self.reply(200, {"ok": True})
        if rate_limited(ip):
            return self.reply(429, {"ok": False, "error": "Слишком много заявок. Попробуйте через несколько минут."})

        order, error = validate(data)
        if error:
            return self.reply(400, {"ok": False, "error": error})

        try:
            send_email(build_email(order, ip))
        except Exception as err:  # noqa: BLE001 — любая ошибка SMTP должна вернуть клиенту понятный ответ
            print(f"Ошибка отправки письма: {err!r}", file=sys.stderr, flush=True)
            save_order(order, ip, sent=False)
            return self.reply(502, {"ok": False, "error": "Не удалось отправить заявку."})
        save_order(order, ip, sent=True)
        return self.reply(200, {"ok": True})

    def log_message(self, fmt, *args):
        print(f"{self.headers.get('X-Real-IP') or self.client_address[0]} {fmt % args}", flush=True)


def send_test() -> None:
    """sudo ... mailer.py --test — отправить пробное письмо и проверить настройки SMTP."""
    order = {"name": "Тестовая заявка", "phone": "+375 33 000 00 00", "email": MAIL_TO,
             "comment": "Это проверка настроек почты. Если вы видите это письмо — всё работает.",
             "sample": True, "n4": 1, "n18": 0}
    send_email(build_email(order, "127.0.0.1"))
    print(f"✓ Тестовое письмо отправлено на {MAIL_TO}")


if __name__ == "__main__":
    if not DRY_RUN and not (SMTP_USER and SMTP_PASSWORD):
        sys.exit("Не заданы SMTP_USER и SMTP_PASSWORD (см. /etc/freshoil-mailer.env)")
    if "--test" in sys.argv:
        send_test()
        sys.exit(0)
    server = ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), Handler)
    print(f"FreshOil mailer слушает 127.0.0.1:{LISTEN_PORT}, письма → {MAIL_TO}", flush=True)
    server.serve_forever()
