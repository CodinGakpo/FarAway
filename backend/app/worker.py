from celery import Celery
from app.config import REDIS_URL

# Initialize Celery app connected to Redis
celery_app = Celery(
    "freightshare",
    broker=REDIS_URL,
    backend=REDIS_URL,
    include=["app.tasks"]
)

# Celery configurations
celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="Asia/Kolkata",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=300, # 5 minutes max per task
)
