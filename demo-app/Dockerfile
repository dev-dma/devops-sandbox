FROM python:3.11-slim
WORKDIR /app
RUN pip install flask --no-cache-dir
COPY app.py .
ENV ENV_ID=unknown ENV_NAME=unknown
EXPOSE 3000
CMD ["python", "app.py"]
