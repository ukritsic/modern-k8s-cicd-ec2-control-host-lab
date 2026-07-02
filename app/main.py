import os
from fastapi import FastAPI

app = FastAPI(title="Modern Kubernetes CI/CD Lab")

APP_VERSION = os.getenv("APP_VERSION", "local")


@app.get("/")
def root() -> dict[str, str]:
    return {
        "message": "Hello from Kubernetes on EC2",
        "version": APP_VERSION,
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
