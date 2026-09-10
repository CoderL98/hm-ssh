# Multi-stage build for hm-ssh-server
FROM rust:1.85-bookworm AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock* ./
COPY src ./src
COPY migrations ./migrations
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/target/release/hm-ssh-server /usr/local/bin/hm-ssh-server
COPY migrations ./migrations
COPY .env.example ./
ENV BIND=0.0.0.0:8080 \
    DATABASE_URL=sqlite:/data/hmssh.db \
    JWT_SECRET=change-me-in-production
VOLUME ["/data"]
EXPOSE 8080
CMD ["hm-ssh-server"]
