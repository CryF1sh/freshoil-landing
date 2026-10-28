# FreshOil — лендинг

Статический одностраничный сайт (HTML + CSS + JS, без сборки и без базы данных).
Ниже полная инструкция, как запустить его на сервере Ubuntu с nginx и подключить к домену с HTTPS.

## Что в репозитории

```
index.html                 — сам лендинг
404.html                   — страница «не найдено»
favicon.svg                — иконка сайта
robots.txt, sitemap.xml    — для поисковиков (домен подставляется автоматически)
deploy/setup.sh            — первая установка на сервер (одна команда)
deploy/update.sh           — обновление сайта после изменений в GitHub
deploy/publish.sh          — копирует файлы сайта в /var/www/<домен> (его вызывают два скрипта выше)
deploy/nginx-freshoil.conf — шаблон конфига nginx
```

---

## Шаг 0. Что понадобится

| Что | Где взять |
|---|---|
| **Домен** (например `freshoil.by`) | купленный у регистратора (hoster.by, reg.ru, nic.ru и т.д.) |
| **Доступ к DNS домена** | личный кабинет регистратора |
| **IP-адрес сервера** | панель хостинга, где арендован сервер |
| **SSH-доступ к серверу** | логин (обычно `root` или пользователь с `sudo`) и пароль или ключ |
| **Email** | для уведомлений Let's Encrypt о сертификате |

---

## Шаг 1. Направить домен на сервер (DNS)

В личном кабинете регистратора откройте **управление DNS** домена и создайте две записи:

| Тип | Имя (хост) | Значение | TTL |
|---|---|---|---|
| `A` | `@` (или пусто, или сам домен) | `IP_ВАШЕГО_СЕРВЕРА` | 3600 |
| `A` | `www` | `IP_ВАШЕГО_СЕРВЕРА` | 3600 |

Если там уже есть старые `A`-записи для `@` или `www` (например, на «парковку» регистратора), **удалите их**.

### Если DNS ведётся в Cloudflare

1. [dash.cloudflare.com](https://dash.cloudflare.com) → **Add a domain** → `freshoil.by` → план **Free**.
2. В списке записей, который Cloudflare найдёт сам, удалите все `A`/`AAAA`/`CNAME` для `@` и `www`. Затем добавьте:

   | Type | Name | IPv4 address | Proxy status |
   |---|---|---|---|
   | `A` | `@` | `IP_ВАШЕГО_СЕРВЕРА` | **DNS only** (серое облако) |
   | `A` | `www` | `IP_ВАШЕГО_СЕРВЕРА` | **DNS only** (серое облако) |

3. Cloudflare покажет два своих nameserver'а (вида `xxx.ns.cloudflare.com`). У регистратора домена в настройках **DNS-серверов (NS)** замените старые серверы на эти два. Если у регистратора включён DNSSEC, сначала выключите его.
4. Дождитесь письма от Cloudflare «domain is active» (обычно от 15 минут до нескольких часов).

**Почему «DNS only»:** с серым облаком Cloudflare только хранит DNS, а трафик идёт напрямую на сервер, и `setup.sh` выпустит сертификат без дополнительных настроек. Оранжевое облако (прокси) включать необязательно. Если всё же включаете, то только после успешного `setup.sh`, и в Cloudflare → **SSL/TLS** выберите режим **Full (strict)**. Иначе сайт уйдёт в бесконечный редирект. Учтите, что у части посетителей из России Cloudflare-прокси работает медленно.

Изменения расходятся от 5 минут до нескольких часов. Проверить можно с любого компьютера:

```bash
nslookup freshoil.by
```

Когда в ответе появился IP вашего сервера, можно переходить дальше. Пока ждёте DNS, можно сделать шаги 2–4.

---

## Шаг 2. Подключиться к серверу

С компьютера (Windows: PowerShell или Терминал; macOS/Linux: Терминал):

```bash
ssh root@IP_ВАШЕГО_СЕРВЕРА
```

Если входите не под `root`, перед командами ниже пишите `sudo` (в инструкции он уже стоит).

---

## Шаг 3. Проверить сервер

```bash
sudo apt update
sudo apt install -y git
nginx -v
sudo systemctl status nginx --no-pager
```

У nginx должно быть `active (running)`. Если не запущен:

```bash
sudo systemctl enable --now nginx
```

**Порты 80 и 443** должны быть открыты:
- скрипт сам откроет их в `ufw`, если тот включён;
- если у хостинга есть свой **firewall / группы безопасности** в веб-панели, откройте там входящие TCP **80** и **443** вручную.

---

## Шаг 4. Скачать проект с GitHub на сервер

### Вариант А: репозиторий публичный (проще)

```bash
sudo git clone https://github.com/CryF1sh/freshoil-landing.git /opt/freshoil-landing
```

### Вариант Б: репозиторий приватный (через deploy key)

1. Создайте ключ на сервере:

   ```bash
   sudo ssh-keygen -t ed25519 -f /root/.ssh/freshoil_deploy -N "" -C "freshoil-server"
   ```

2. Выведите публичный ключ:

   ```bash
   sudo cat /root/.ssh/freshoil_deploy.pub
   ```

3. На GitHub: репозиторий → **Settings → Deploy keys → Add deploy key**, вставьте ключ, галочку «Allow write access» **не** ставьте.

4. Скажите git использовать этот ключ для GitHub:

   ```bash
   printf 'Host github.com\n  IdentityFile /root/.ssh/freshoil_deploy\n  IdentitiesOnly yes\n' | sudo tee -a /root/.ssh/config
   ```

5. Склонируйте репозиторий:

   ```bash
   sudo git clone git@github.com:CryF1sh/freshoil-landing.git /opt/freshoil-landing
   ```

   На вопрос `Are you sure you want to continue connecting?` ответьте `yes`.

---

## Шаг 5. Установить сайт (одна команда)

Замените домен и email на свои:

```bash
sudo bash /opt/freshoil-landing/deploy/setup.sh freshoil.by you@gmail.com
```

Что делает скрипт:

1. ставит `certbot` (для бесплатного HTTPS) и `rsync`; nginx у вас уже есть, его не трогает;
2. проверяет, что DNS домена указывает на этот сервер;
3. копирует файлы сайта в `/var/www/freshoil.by` (папку `deploy`, `README.md` и `.git` не копирует);
4. создаёт конфиг `/etc/nginx/sites-available/freshoil.by`, включает его, проверяет `nginx -t` и перезагружает nginx;
5. выпускает сертификат Let's Encrypt и включает автоматический редирект `http → https`.

В конце появится строка `✓ Готово! Сайт доступен: https://freshoil.by`.

> Другие сайты на этом nginx скрипт не трогает: он добавляет отдельный файл конфига только для вашего домена.

---

## Шаг 6. Проверить

- Откройте `https://ваш-домен`: должен открыться лендинг с замком в адресной строке.
- `http://ваш-домен` и `www.ваш-домен` должны перенаправлять на `https://`.
- `https://ваш-домен/любая-ерунда` должна показать страницу 404 FreshOil.

Сертификат продлевается **автоматически** (certbot ставит таймер). Проверить, что продление сработает:

```bash
sudo certbot renew --dry-run
```

---

## Как обновлять сайт

1. Измените `index.html` в GitHub (прямо в браузере: файл → иконка ✏️ → **Commit changes**) или запушьте изменения со своего компьютера.
2. На сервере выполните:

   ```bash
   sudo bash /opt/freshoil-landing/deploy/update.sh
   ```

Скрипт подтянет свежую версию и опубликует её. Перезагружать nginx не нужно.

---

## Если что-то пошло не так

| Симптом | Причина и решение |
|---|---|
| `✗ У домена нет A-записи` | DNS ещё не обновился или запись не создана. Проверьте шаг 1, подождите и запустите `setup.sh` ещё раз. |
| `⚠ A-запись указывает не на этот сервер` | В DNS указан другой IP. Исправьте у регистратора. |
| Certbot: `Timeout during connect` / `Connection refused` | Закрыт порт 80. Откройте 80/443 в firewall хостинга (шаг 3). |
| Certbot: `too many failed authorizations` | Слишком много неудачных попыток. Подождите час, исправьте DNS или порты и повторите. |
| Открывается «Welcome to nginx!» | Есть конфиг `default`, который перехватывает домен. Выполните `sudo rm /etc/nginx/sites-enabled/default && sudo systemctl reload nginx` (только если на сервере нет других сайтов в этом файле). |
| `nginx -t` выдаёт ошибку | Посмотрите текст ошибки: скорее всего, тот же домен уже описан в другом конфиге. Найти его можно так: `grep -r "server_name" /etc/nginx/sites-enabled/`. |
| Сайт открывается, но изменения не видны | Запустите `update.sh` и обновите страницу с `Ctrl+F5`. |

Полезные команды:

```bash
sudo nginx -t                              # проверить конфиг
sudo systemctl reload nginx                # применить конфиг
sudo tail -n 50 /var/log/nginx/error.log   # последние ошибки
sudo certbot certificates                  # какие сертификаты выпущены
```

---

## Ручная установка (без скрипта)

Если хотите сделать всё сами по шагам:

```bash
DOMAIN=freshoil.by
sudo apt install -y certbot python3-certbot-nginx rsync
sudo bash /opt/freshoil-landing/deploy/publish.sh $DOMAIN
echo "DOMAIN=$DOMAIN" | sudo tee /etc/freshoil.conf
sed -e "s|__DOMAIN__|$DOMAIN|g" -e "s|__WEBROOT__|/var/www/$DOMAIN|" \
  /opt/freshoil-landing/deploy/nginx-freshoil.conf | sudo tee /etc/nginx/sites-available/$DOMAIN
sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --redirect
```

---

## Про форму заявки

Сайт статический, поэтому форма не отправляет письмо сама: она открывает почтовую программу посетителя с готовым письмом на `freshmetka@gmail.com`. Если почтовая программа не настроена (частый случай на компьютерах), в окне подтверждения есть кнопка **«Скопировать заявку»** и контакты для связи.

Чтобы заявки приходили автоматически (в Telegram или на почту, без участия посетителя), нужен небольшой обработчик на сервере. Его можно добавить отдельным шагом.
