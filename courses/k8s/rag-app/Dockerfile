# RAG app image — Python 3.12, fastembed (ONNX, no PyTorch), FastAPI.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    EMBED_MODEL=BAAI/bge-small-en-v1.5 \
    HF_HUB_DISABLE_TELEMETRY=1 \
    FASTEMBED_CACHE_PATH=/opt/models

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download the embedding model into the image so pods start fast and offline.
RUN python -c "from fastembed import TextEmbedding; TextEmbedding(model_name='$EMBED_MODEL')"

COPY app/ ./app/

EXPOSE 8000

# Run as non-root.
RUN useradd -u 10001 -m appuser && chown -R appuser /app /opt/models
USER appuser

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
