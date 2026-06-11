import logging
from app.worker import celery_app
from app.database import SessionLocal
from app.services.match_service import MatchService

logger = logging.getLogger(__name__)

@celery_app.task(name="app.tasks.run_matching_job")
def run_matching_job(load_id: int) -> dict:
    """
    Celery background worker job.
    Executes PostGIS overlap math and triggers LLM summaries.
    """
    logger.info(f"--- Starting Celery Matching Job for Load ID: {load_id} ---")
    db = SessionLocal()
    try:
        matches = MatchService.run_spatial_matching(load_id=load_id, db=db)
        logger.info(f"--- Celery Matching Job finished. Created {len(matches)} matches ---")
        return {
            "status": "success",
            "load_id": load_id,
            "matches_created": len(matches)
        }
    except Exception as e:
        logger.error(f"Error executing matching job for load {load_id}: {str(e)}")
        return {
            "status": "error",
            "load_id": load_id,
            "error": str(e)
        }
    finally:
        db.close()
