FROM python:3.11-slim

WORKDIR /app

COPY setup.py .
COPY requirements.txt .
COPY Folly/ Folly/
COPY example_challenges/ example_challenges/

RUN pip install --no-cache-dir .

EXPOSE 5000 5001
