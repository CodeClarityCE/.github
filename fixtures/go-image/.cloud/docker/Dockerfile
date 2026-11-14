# syntax=docker/dockerfile:1

# Same base images as the plugin Dockerfiles.
FROM golang:1.27.3-alpine@sha256:d200d2dd76b03a99b52651fd1325aff7dcd35422c35c01bac56571b0507f3deb AS plugin-build
WORKDIR /src
COPY . .
RUN go build -o plugin && false

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS plugin
WORKDIR /app
COPY --from=plugin-build /src/plugin /src/config.json ./
ENTRYPOINT ["./plugin"]
