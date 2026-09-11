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

# Download 3x-ui during build
RUN set -eux; \
    curl -fL --retry 3 --connect-timeout 20 \
      "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz" \
      -o /tmp/xui.tar.gz; \
    tar -xzf /tmp/xui.tar.gz -C /app; \
    test -f /app/x-ui/x-ui; \
    chmod +x /app/x-ui/x-ui; \
    rm -f /tmp/xui.tar.gz

# ---- Writable DATA ----
RUN rm -rf /app/data \
    && ln -s /tmp/xui-data /app/data

# ---- Writable Xray BIN / config ----
RUN mv /app/x-ui/bin /opt/xui-bin-seed \
    && ln -s /tmp/xui-bin /app/x-ui/bin

COPY --from=launcher-builder /out/launcher /usr/local/bin/launcher

EXPOSE 2053

CMD ["sh", "-c", "\
mkdir -p /tmp/xui-data/logs /tmp/xui-bin && \
cp -a /opt/xui-bin-seed/. /tmp/xui-bin/ && \
chmod -R u+rwX /tmp/xui-data /tmp/xui-bin && \
find /tmp/xui-bin -type f -exec chmod +x {} \\; && \
exec /usr/local/bin/launcher"]
