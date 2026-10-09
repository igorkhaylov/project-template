# syntax=docker/dockerfile:1
#
# Build context is THIS directory (`docker build frontend/`). The image is a static file
# server: one build serves every environment, because environment-specific values are
# read at runtime from /config.js (rendered by nginx from APP_* env vars), never baked
# in. Only build identity (VITE_APP_VERSION) is passed at build time.

# ----------------------------- build -----------------------------
FROM node:24-alpine AS build

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
ARG VITE_APP_VERSION=dev
ENV VITE_APP_VERSION=$VITE_APP_VERSION
RUN npm run build

# ----------------------------- runtime -----------------------------
# Unprivileged nginx: runs as uid 101 and listens on 8080, so the container needs no
# root and no capabilities (Kubernetes runAsNonRoot-friendly).
FROM nginxinc/nginx-unprivileged:stable-alpine AS runtime

# The image entrypoint renders /etc/nginx/templates/*.template with envsubst. Restrict
# substitution to APP_* so nginx's own $variables are left alone, and define every APP_*
# variable here so an unset one renders empty instead of a literal "${APP_…}".
ENV NGINX_ENVSUBST_FILTER=^APP_ \
    APP_API_BASE_URL="" \
    APP_ENVIRONMENT="prod"

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 8080
