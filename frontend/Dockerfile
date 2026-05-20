FROM ghcr.io/cirruslabs/flutter:3.41.4 AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

ARG REST_BASE_URL=
ARG MQTT_TCP_HOST=
ARG MQTT_TCP_PORT=
ARG MQTT_WS_URL=
ARG MQTT_USERNAME=
ARG MQTT_PASSWORD=

RUN set -eux; \
    flutter build web --release \
      ${REST_BASE_URL:+--dart-define=REST_BASE_URL=${REST_BASE_URL}} \
      ${MQTT_TCP_HOST:+--dart-define=MQTT_TCP_HOST=${MQTT_TCP_HOST}} \
      ${MQTT_TCP_PORT:+--dart-define=MQTT_TCP_PORT=${MQTT_TCP_PORT}} \
      ${MQTT_WS_URL:+--dart-define=MQTT_WS_URL=${MQTT_WS_URL}} \
      ${MQTT_USERNAME:+--dart-define=MQTT_USERNAME=${MQTT_USERNAME}} \
      ${MQTT_PASSWORD:+--dart-define=MQTT_PASSWORD=${MQTT_PASSWORD}}

FROM nginx:1.27-alpine

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80
