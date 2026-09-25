FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

RUN groupadd -r app && useradd -r -g app app

COPY requirements.txt ./
RUN pip install -r requirements.txt

COPY app.py rag.py bot.py ./
RUN chown -R app:app /app
USER app

ENV PORT=3978
EXPOSE 3978

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:3978/health', timeout=3).status==200 else 1)"

CMD ["python", "-u", "app.py"]
