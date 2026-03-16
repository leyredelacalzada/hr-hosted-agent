FROM python:3.12-slim

WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

COPY requirements.txt ./
COPY main.py ./

RUN uv pip install --system --pre -r requirements.txt

EXPOSE 8088

CMD ["python", "main.py"]
