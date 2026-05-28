# Python Parser Dockerfile
FROM docker.io/library/python:3.11-slim

WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies (no gcc needed — all pure-python packages)
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY new_checkpoint_data.py .
COPY links.txt .

# Create non-root user
RUN adduser --disabled-password --gecos '' appuser && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import redis; r=redis.Redis(host='checkpoint-keydb', port=6379, decode_responses=True); r.ping()" || exit 1

# Run the parser
CMD ["python", "new_checkpoint_data.py"]
