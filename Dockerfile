# Stage 1: Build
FROM python:3.11-slim AS builder

WORKDIR /build

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Runtime (slim, rootless)
FROM python:3.11-slim

WORKDIR /app

# Copy installed Python packages
COPY --from=builder /install /usr/local

# Copy application code
COPY --chown=nonroot:nonroot . .

# Create non-root user and switch
RUN groupadd -r nonroot && useradd -r -g nonroot nonroot
RUN chown -R nonroot:nonroot /app
USER nonroot

# Default command
ENTRYPOINT ["python3", "-m", "ad_miner"]