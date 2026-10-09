# Отклонения от django-template

Реестр всего, чем бэкенд и обвязка этого шаблона отличаются от
[django-template](https://github.com/igorkhaylov/django-template) (состояние на коммит
`156ba16`, 2026-09-07). Первичный обзор проведён 2026-10-09: все пункты приняты, A8
уточнён. Дальше файл служит картой расхождений: при переносе улучшений из django-template
сюда (или обратно) по нему видно, какие файлы и почему разошлись. Чтобы откатить или
изменить пункт, достаточно назвать его идентификатор («B7 откатить»).

Правило ведения: любое изменение файла, пришедшего из django-template, получает строку
здесь, с идентификатором. Новые файлы перечислены отдельно (раздел C), они ничего в
оригинале не меняют. Статус: **в силе** (так сейчас в коде) или **откачено** (возвращено
к оригиналу по решению владельца).

## A. Раскладка и ops (перенос файлов, compose, CI)

| ID | Где | Что изменено | Зачем | Статус |
|---|---|---|---|---|
| A1 | `backend/Dockerfile`, `Dockerfile.dev`, `.dockerignore` | Перенесены из корня в `backend/`; контекст сборки = `backend/`, `COPY backend/ .` → `COPY . .`; в `.dockerignore` убраны префиксы `backend/`, добавлено `**/*.mo` | Компонент самодостаточен: собирается из своей папки в монорепо, в CI и отдельно | в силе |
| A2 | `ops/compose/docker-compose*.yml` | Четыре compose-файла перенесены из корня в `ops/compose/`; запуск через Makefile с `--project-directory .` (пути `./backend`, `./ops/nginx`, `./.env` от корня) | Вся оркестрация в `ops/` | в силе |
| A3 | `ops/nginx/`, `ops/scripts/`, `ops/minio/` | Перенесены из корня; в скриптах `cd "$(dirname "$0")/../.."`, `REPO_ROOT` на два уровня вверх, путь к политикам `ops/minio/policies/` | То же | в силе |
| A4 | `.gitlab-ci.yml` | Удалён | Дефолт шаблона — GitHub Actions; GitLab позже (модель описана в `docs/deploy.md`) | в силе |
| A5 | `.github/workflows/` | `build-push.yml` + `deploy.yml` заменены на `backend.yml`, `frontend.yml`, `deploy.yml`: фильтры по путям, образы `ghcr.io/<owner>/<repo>/backend` и `/frontend` (было `ghcr.io/<owner>/<repo>`), проверка актуальности `api/openapi.yaml`, build-arg `APP_VERSION`, деплой одного компонента через `ops/scripts/deploy.sh` | Две команды, независимые пайплайны и деплои | в силе |
| A6 | `Makefile` | Compose через `ops/compose` + `--project-directory .`; убран `EXEC := --workdir /app/backend` (dev-образ сам в `/app/backend`); добавлены `ps`, `release`, `api-schema`, `fe-*`; `init` дополнительно делает `npm ci` | Новая раскладка, фронтенд, контракт | в силе |
| A7 | `ops/compose/docker-compose.dev.yml`, `backend/Dockerfile.dev` | Монтируется `./backend:/app/backend` вместо `.:/app`; `WORKDIR /app/backend` | В контейнер бэкенда не попадают `frontend/node_modules` и прочее | в силе |
| A8 | `ops/scripts/ensure_minio.sh` | Сервер и клиент из одного образа `pgsty/silo:RELEASE.2026-09-16T00-00-00Z` (было `pgsty/silo:…08-06` + клиент `minio/mc:latest`): провижининг запускает `mcli` из образа silo, переменная `MINIO_MC_IMAGE` → `MINIO_MCLI_IMAGE` (по умолчанию = образ сервера) | `minio/mc` отозван с Docker Hub и quay.io, dl.min.io отдаёт 410; в django-template `make init` на чистой машине из-за этого падает. Отдельного образа `pgsty/mcli` не существует, бинарник `mcli` лежит в образе silo | в силе |
| A9 | `ops/scripts/deploy.sh` | Новый серверный скрипт: пин образов в `.env` + `pull` + `up -d` | Деплой одного компонента без касания второго; его же зовёт CI | в силе |
| A10 | `ops/nginx/nginx.conf`, `nginx.dev.conf` | Второй upstream (frontend) и маршрутизация по регулярке префиксов бэкенда; `proxy_http_version 1.1` + `Connection ""` для keepalive к upstream; dev-конфиг проксирует `/` на Vite на хосте с поддержкой websocket (HMR); из JSON-лога убрано поле `cua` (`$http_custom_user_agent`) | Один origin для SPA и API | в силе |
| A11 | `.env.example` | Идентификаторы `django-template` → `project-template`; добавлены `FRONTEND_IMAGE`, `APP_API_BASE_URL`; `BACKEND_IMAGE` с суффиксом `/backend`; `DJANGO_ALLOWED_HOSTS=localhost` (было `localhost,backend,`); в CSRF/CORS добавлен `http://localhost:5173`; `GUNICORN_WORKERS=2` (было 4); комментарии про `DATABASE_URL`/`REDIS_URL` | Два образа, Vite dev server, пункты B3/B7/B8/B13 | в силе |
| A12 | `docs/`, `README.md` | `adapting.md` и `deploy.md` переписаны под новую раскладку; в `backup.md`, `uv.md` обновлены пути; README разделён на корневой и `backend/README.md` | Документация соответствует коду | в силе |
| A13 | `.vscode/settings.json`, новый `.vscode/extensions.json` | ESLint с рабочей директорией `frontend`; Prettier как форматтер для ts/tsx/js/css; путь к Tailwind-стилям для расширения; слова cSpell; рекомендации расширений (ESLint, Prettier, Tailwind, Ruff, cSpell) | Тулинг фронтенда (Prettier, Tailwind v4, flat ESLint) в монорепо | в силе |

## B. Бэкенд: изменения в файлах из django-template

| ID | Файл | Что изменено | Зачем | Статус |
|---|---|---|---|---|
| B1 | `config/settings/base.py` | Добавлена `APP_VERSION = config("APP_VERSION", default="dev")` | Версия сборки (git sha/тег) из build-arg, отдаётся в `/api/v1/meta/` | в силе |
| B2 | `config/settings/base.py` | Дефолт `DJANGO_APP_NAME`: `"AppName"` → `"ProjectTemplate"` | Детерминированный заголовок `api/openapi.yaml` без `.env`, который переименовывает `scripts/new_project.sh` | в силе |
| B3 | `config/settings/base.py` | Удалён автодобавление `localhost` в `ALLOWED_HOSTS` (блок `if ALLOWED_HOSTS and "localhost" not in ALLOWED_HOSTS`) | Healthcheck контейнера ходит на `/readyz/`, который отвечает до проверки Host (B5) | в силе |
| B4 | `config/settings/base.py` | Удалён `SECURE_REDIRECT_EXEMPT = [r"^healthcheck/"]` | Пробы отвечаются до `SecurityMiddleware` (B5); маршрут `/healthcheck/` убран (B12) | в силе |
| B5 | `config/settings/base.py` | `common.middleware.HealthCheckMiddleware` первым в `MIDDLEWARE` | `/healthz/` и `/readyz/` отвечают до валидации Host: пробы Kubernetes приходят с IP пода в `Host` | в силе |
| B6 | `config/settings/base.py` | `django_celery_beat` в `INSTALLED_APPS` | Расписание beat в БД, контейнер без состояния (см. B11) | в силе |
| B7 | `config/settings/base.py` | `DATABASES`: при заданном `DATABASE_URL` используется `dj_database_url.parse(...)`, иначе прежний набор `POSTGRES_*` (поведение без `DATABASE_URL` не изменилось) | Один connection string для Secret в k8s и managed Postgres | в силе |
| B8 | `config/settings/base.py` | Добавлен `REDIS_URL` (база без номера БД, по умолчанию из `REDIS_HOST`/`REDIS_PORT`); `CACHES.LOCATION = f"{REDIS_URL}/1"` | То же для Redis | в силе |
| B9 | `config/settings/third_party.py` | `SPECTACULAR_SETTINGS["ENUM_NAME_OVERRIDES"] = {"HealthStateEnum": "common.health.HEALTH_STATES"}` | Один enum-компонент для статусов проб вместо `StatusEnum`/`DatabaseEnum`/`CacheEnum` и предупреждений о коллизиях | в силе |
| B10 | `config/settings/dev.py` | Debug toolbar подключается только если модуль импортируется (`find_spec("debug_toolbar")`) | `make up` (prod-образ без dev-группы) с `ENVIRONMENT=dev` из `.env` иначе падает на импорте; в django-template это тоже воспроизводится | в силе |
| B11 | `config/celery.py` | Broker/result из `settings.REDIS_URL` (B8); `beat_scheduler = DatabaseScheduler`; удалён `beat_schedule_filename = "/tmp/celerybeat-schedule"` | Beat без локального файла: ничего не хранить в поде/томе | в силе |
| B12 | `config/urls.py` | Удалён маршрут `/healthcheck/` (lambda) и модульный docstring; добавлены `/healthz/`, `/readyz/`, `/api/v1/` (`config/api_v1.py`), `/api/schema/`, `/api/docs/` | Пробы liveness/readiness с описанием в схеме; маршрутизация API с версией; Swagger | в силе |
| B13 | `scripts/entrypoint.sh` | Оставлен только запуск gunicorn (дефолт `GUNICORN_WORKERS` 4 → 2); `compilemessages`, `migrate`, `wait_for_storage`, `collectstatic`, `createsuperuserauto` вынесены в новый `scripts/release.sh` (compilemessages — в Dockerfile, B14) | Миграции не в web-процессе: N реплик стартуют без гонки; в compose это сервис `release` (D1) | в силе |
| B14 | `Dockerfile` | Контекст `backend/` (A1); `.po` → `.mo` компилируются при сборке (`msgfmt`); `ARG/ENV APP_VERSION`; добавлен `CMD ["bash", "scripts/entrypoint.sh"]` (в оригинале команду задавал только compose) | Образ не пишет в себя на старте; версия сборки; `docker run` и bare-Deployment работают без команды | в силе |
| B15 | `Dockerfile.dev` | `WORKDIR /app/backend` (было `/app`) | A7 | в силе |
| B16 | `pyproject.toml`, `uv.lock` | `name = "app"` → `"project-template-backend"`; добавлены `dj-database-url` (B7) и `django-celery-beat` (B6, B11); lock перегенерирован | — | в силе |
| B17 | `tests/test_common.py` | `test_healthcheck` (`/healthcheck/`) удалён (B12); добавлены тесты `/healthz/` с чужим Host, `/readyz/`, совпадения вьюх и middleware, наличия путей в схеме, `/api/v1/meta/` | Покрытие новых контрактов | в силе |
| B18 | `locale/ru/.../django.po`, `apps/users/locale/ru/.../django.po` | В комментарии заголовка `django-template` → `project-template` (английские `.po` такого заголовка не имеют и не тронуты) | Косметика; `scripts/new_project.sh` подставит имя проекта | в силе |
| B19 | `apps/common/firebase.py` | В docstring путь `docker-compose.prod.yml` → `ops/compose/docker-compose.prod.yml` | Комментарий, актуальный путь | в силе |

## C. Бэкенд: новые файлы (оригинал не затронут)

| ID | Файл | Что это |
|---|---|---|
| C1 | `apps/common/health.py` | Функции `liveness()` / `readiness()` (проверка БД и кэша) и `HEALTH_STATES` |
| C2 | `apps/common/middleware.py` | `HealthCheckMiddleware`: отвечает на `/healthz/`, `/readyz/` до валидации Host и HTTPS-редиректа |
| C3 | `apps/common/serializers.py` | `HealthSerializer`, `ReadinessSerializer`, `ReadinessChecksSerializer`, `LanguageSerializer`, `MetaSerializer` |
| C4 | `apps/common/views.py` | `HealthzView`, `ReadyzView`, `MetaView` (`/api/v1/meta/`: имя, версия, окружение, языки) |
| C5 | `apps/common/urls.py`, `config/api_v1.py` | Маршруты приложения и таблица `/api/v1/` (по одному `include` на приложение) |
| C6 | `scripts/release.sh` | Шаг релиза: migrate → wait_for_storage → collectstatic → createsuperuserauto |
| C7 | `backend/README.md` | Документация бэкенда (часть прежнего корневого README) |

## D. Compose: сервисы бэкенда

| ID | Где | Что изменено | Зачем | Статус |
|---|---|---|---|---|
| D1 | `docker-compose.yml`, `docker-compose.prod.yml` | Новый одноразовый сервис `release` (`bash scripts/release.sh`, `restart: "no"`); `backend` зависит от него с `condition: service_completed_successfully`; у `backend` нет `command:` (используется `CMD` образа, B14) | B13 | в силе |
| D2 | те же | Healthcheck `backend`: `curl -f http://localhost:8000/healthcheck/` → `curl -fsS http://localhost:8000/readyz/`; `start_period` 60s → 20s (миграций перед стартом gunicorn больше нет) | B12, B13 | в силе |
| D3 | те же | У `celery-beat` удалён healthcheck по mtime файла `/tmp/celerybeat-schedule*` | С `DatabaseScheduler` (B11) файла нет; beat нечего пробовать, при падении процесса контейнер перезапускается. Альтернатива при откате B6/B11: вернуть оригинальный healthcheck | в силе |
| D4 | те же | Healthcheck `celery` (`celery inspect ping`) — без изменений | — | — |
| D5 | те же, `docker-compose.dev.yml` | Добавлены сервисы `frontend` и edge-`nginx` с маршрутизацией; `nginx` зависит от `frontend` | Фронтенд в стеке | в силе |
| D6 | `docker-compose.test.yml` | Контекст `./backend`; сервис используется также для генерации `api/openapi.yaml` (`make api-schema`) | A1, контракт | в силе |

## E. Не отклонения, но стоит знать

- `GUNICORN_WORKERS`: в `.env.example` 2 вместо 4 (A11), дефолт в entrypoint тоже 2 (B13). Логика: масштабировать репликами.
- Пробы: `/healthz/` ничего не проверяет намеренно (liveness), `/readyz/` отдаёт 503 с перечнем проверок. Оригинальный `/healthcheck/` эквивалентен `/healthz/`, но не обходил проверку Host.
- При откате B6/B11 (django-celery-beat) нужно одновременно вернуть D3 и строку `beat_schedule_filename`.
- При откате B13 (разделение entrypoint) нужно одновременно убрать D1 и вернуть `start_period: 60s` в D2; `release.sh` можно оставить для Kubernetes.
