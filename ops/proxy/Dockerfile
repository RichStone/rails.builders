# Rebuild the deployed v0.9.2 source with the emSign mitigation and current CAs.
# docker build --pull --platform linux/amd64 -f ops/proxy/Dockerfile -t richwhale/kamal-proxy:v0.9.2.20261024 .
FROM --platform=$BUILDPLATFORM golang:1.27.3 AS build

WORKDIR /app
ADD https://github.com/basecamp/kamal-proxy.git#c195e5bfd056ba311a391bba30e9dbf4689be2ec .

ARG TARGETOS TARGETARCH
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates && \
    go test ./... && \
    GOOS=$TARGETOS GOARCH=$TARGETARCH make

FROM basecamp/kamal-proxy:v0.9.2
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /app/bin/kamal-proxy /usr/local/bin/
