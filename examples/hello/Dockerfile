# Build stage
FROM rust:1.85-slim AS builder
WORKDIR /src

# Cache dependencies separately from source
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main(){}" > src/main.rs && echo "" > src/lib.rs \
    && cargo build --release \
    && rm -rf src

COPY src ./src
RUN touch src/main.rs src/lib.rs && cargo build --release

# Runtime stage
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/hello /usr/local/bin/hello
ENTRYPOINT ["hello"]
