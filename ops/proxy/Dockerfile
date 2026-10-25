# Rebuild the current proxy release with the Go security patches and current CAs.
# docker build --pull --platform linux/amd64 -f ops/proxy/Dockerfile -t richwhale/kamal-proxy:v0.10.2.20261025 .
FROM --platform=$BUILDPLATFORM golang:1.27.3 AS build

WORKDIR /app
ADD https://github.com/basecamp/kamal-proxy.git#3b4ad579bcf5db316a86d27bd896c1e30874f192 .

ARG TARGETOS TARGETARCH
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates && \
    go test ./... && \
    GOOS=$TARGETOS GOARCH=$TARGETARCH make VERSION=0.10.2

FROM basecamp/kamal-proxy:v0.10.2
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /app/bin/kamal-proxy /usr/local/bin/
