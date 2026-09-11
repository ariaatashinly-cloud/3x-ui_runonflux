# Build the Go launcher/reverse-proxy
FROM golang:1.22-alpine AS launcher-builder

WORKDIR /src
COPY go.mod ./
COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/launcher .

# Runtime image
FROM alpine:3.22

RUN apk add --no-cache \
    ca-certificates \
    curl \
    tar \
    gzip \
    bash \
    tzdata \
    openssl

WORKDIR /app

# Download 3x-ui during IMAGE BUILD
RUN set -eux; \
    curl -fL --retry 3 --connect-timeout 20 \
      "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz" \
      -o /tmp/xui.tar.gz; \
    tar -xzf /tmp/xui.tar.gz -C /app; \
    test -f /app/x-ui/x-ui; \
    chmod +x /app/x-ui/x-ui; \
    if [ -d /app/x-ui/bin ]; then find /app/x-ui/bin -type f -exec chmod +x {} \;; fi; \
    rm -f /tmp/xui.tar.gz

# Deplexo runtime is read-only under /app.
# Redirect writable 3x-ui data to /tmp.
RUN rm -rf /app/data && ln -s /tmp/xui-data /app/data

COPY --from=launcher-builder /out/launcher /usr/local/bin/launcher

EXPOSE 2053

CMD ["sh", "-c", "mkdir -p /tmp/xui-data/logs && exec /usr/local/bin/launcher"]
