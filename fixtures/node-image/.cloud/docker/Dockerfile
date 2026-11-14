# syntax=docker/dockerfile:1

# Same toolchain target as the api and frontend Dockerfiles.
FROM node:26.10.0-alpine@sha256:0b36e8c136b94cd4fcf02188228e76c31ad5872eef3fec8cbd2eee500cfd9e80 AS toolchain
ENV COREPACK_HOME=/opt/corepack \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0
WORKDIR /app
RUN npm install -g corepack@0.36.0 --force && corepack enable
COPY package.json ./
RUN corepack install && chmod -R a+rwX /opt/corepack

FROM node:26.10.0-alpine@sha256:0b36e8c136b94cd4fcf02188228e76c31ad5872eef3fec8cbd2eee500cfd9e80 AS app
WORKDIR /app
COPY package.json ./
COPY src/greet.js ./src/
CMD ["node", "-e", "import('./src/greet.js').then((m) => console.log(m.greet('world')))"]
