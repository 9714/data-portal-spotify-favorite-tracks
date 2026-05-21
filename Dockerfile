FROM python:3.12-slim
WORKDIR /app
COPY etl/ etl/
COPY dbt/ dbt/
RUN pip install --no-cache-dir -r etl/requirements.txt
RUN cd /app/dbt && dbt deps --project-dir /app/dbt --profiles-dir /app/dbt
WORKDIR /app/etl
CMD ["python", "main.py"]
