FROM python:3.12-slim
WORKDIR /app
COPY etl/ etl/
RUN pip install --no-cache-dir -r etl/requirements.txt
WORKDIR /app/etl
CMD ["python", "main.py"]
