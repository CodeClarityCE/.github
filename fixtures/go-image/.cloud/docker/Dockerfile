# syntax=docker/dockerfile:1

# Same base images as the plugin Dockerfiles.
FROM golang:1.27.4-alpine@sha256:0a5f7fe796599ff487605987432e7619ae45beeb2fba4c2ce0b907879932aebf AS plugin-build
WORKDIR /src
COPY . .
RUN go build -o plugin

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS plugin
WORKDIR /app
COPY --from=plugin-build /src/plugin /src/config.json ./
ENTRYPOINT ["./plugin"]
