# Export the pinned Honeybadger CLI with a supported Go runtime.
FROM --platform=$BUILDPLATFORM golang:1.27.3 AS build
WORKDIR /src
ADD https://github.com/honeybadger-io/cli.git#10a46bb0d5935b603caea915c4a153e9d1b8ebe0 .
ARG TARGETOS TARGETARCH
RUN go test ./... && \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath \
      -ldflags="-s -w -X github.com/honeybadger-io/cli/cmd.Version=0.10.1+go1.27.3 -X github.com/honeybadger-io/cli/cmd.Commit=10a46bb0d5935b603caea915c4a153e9d1b8ebe0" \
      -o /hb ./cmd/hb

FROM scratch
COPY --from=build /hb /hb
