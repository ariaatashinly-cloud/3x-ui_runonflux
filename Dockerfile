FROM golang:1.22-alpine AS launcher-builder

WORKDIR /src
COPY go.mod ./
COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/launcher .


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

# Download official 3x-ui at build time
RUN set -eux; \
    curl -fL --retry 3 --connect-timeout 20 \
      "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz" \
      -o /tmp/xui.tar.gz; \
    tar -xzf /tmp/xui.tar.gz -C /app; \
    test -f /app/x-ui/x-ui; \
    chmod +x /app/x-ui/x-ui; \
    rm -f /tmp/xui.tar.gz

# Database/log path must be writable
RUN rm -rf /app/data && ln -s /tmp/xui-data /app/data

COPY --from=launcher-builder /out/launcher /usr/local/bin/launcher

# Tell 3x-ui to use a writable copy of Xray/bin
ENV XUI_BIN_FOLDER=/tmp/xui-bin
ENV XUI_ENABLE_FAIL2BAN=false
ENV XUI_SKIP_HSTS=true

EXPOSE 2053

CMD ["sh", "-c", "mkdir -p /tmp/xui-data/logs /tmp/xui-bin && cp -a /app/x-ui/bin/. /tmp/xui-bin/ && chmod +x /tmp/xui-bin/xray 2>/dev/null || true; exec /usr/local/bin/launcher"]
