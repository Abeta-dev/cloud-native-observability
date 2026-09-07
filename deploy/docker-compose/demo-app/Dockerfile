FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o demo-app main.go

FROM alpine:3.19
RUN apk --no-cache add ca-certificates curl
WORKDIR /root/
COPY --from=builder /app/demo-app .
EXPOSE 8080
HEALTHCHECK --interval=5s --timeout=3s --retries=3 CMD curl -f http://localhost:8080/healthz || exit 1
CMD ["./demo-app"]
