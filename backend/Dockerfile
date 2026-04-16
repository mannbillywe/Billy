FROM python:3.11-slim

WORKDIR /app

COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ .

ENV PORT=8080
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT}
