import json
import logging
import os
import uuid
from datetime import datetime
from zoneinfo import ZoneInfo

from dotenv import load_dotenv
from fastapi import APIRouter, BackgroundTasks, Depends
from models.incident import Incident, IncidentAnalysis
from schemas.alert import AlertItem, AlertmanagerWebhook
from sqlmodel import Session, select
from tools import engine, get_session

load_dotenv()

TIME_ZONE = ZoneInfo(os.environ["TIME_ZONE"])
logger = logging.getLogger(__name__)

router = APIRouter()


def now_iso() -> str:
    return datetime.now(tz=TIME_ZONE).isoformat()


def upsert_incident(session: Session, alert: AlertItem) -> str:
    """Create or bump the incident for this alert. Returns incident_id."""
    hostname = alert.labels.get("host", "unknown")
    ip_address = alert.labels.get("ip", "unknown")

    existing = session.exec(
        select(Incident).where(Incident.fingerprint == alert.fingerprint)
    ).first()

    if existing:
        existing.failure_count += 1
        existing.fired_at = now_iso()
        existing.status = "PENDING"
        session.add(existing)
        session.commit()
        logger.info(
            "incident updated",
            extra={
                "incident_id": existing.incident_id,
                "host": hostname,
                "count": existing.failure_count,
            },
        )
        return existing.incident_id

    incident = Incident(
        incident_id=str(uuid.uuid4()),
        fingerprint=alert.fingerprint,
        hostname=hostname,
        ip_address=ip_address,
        status="PENDING",
        fired_at=now_iso(),
        failure_count=1,
    )
    session.add(incident)
    session.commit()
    logger.info(
        "incident created",
        extra={"incident_id": incident.incident_id, "host": hostname},
    )
    return incident.incident_id


async def investigate(incident_id: str) -> None:
    """Runs after the webhook has been acknowledged. Owns its own DB session."""
    with Session(engine) as session:
        incident = session.get(Incident, incident_id)
        if incident is None:
            logger.warning(
                "incident vanished before investigation",
                extra={"incident_id": incident_id},
            )
            return

        incident.status = "INVESTIGATING"
        session.add(incident)
        session.commit()

        try:
            # TODO: agent tool — failed units / containers on incident.hostname
            failed_services: list[str] = []

            # TODO: agent — pull journal lines for those units from Loki, analyse
            analysis: dict = {}

            session.add(
                IncidentAnalysis(
                    id=str(uuid.uuid4()),
                    incident_id=incident_id,
                    created_at=now_iso(),
                    failed_services=json.dumps(failed_services),
                    analysis=json.dumps(analysis),
                )
            )
            incident.status = "ANALYSED"
            session.add(incident)
            session.commit()
            logger.info("analysis saved", extra={"incident_id": incident_id})

            # TODO: notify — telegram / email

        except Exception:
            logger.exception("investigation failed", extra={"incident_id": incident_id})
            incident.status = "FAILED"
            session.add(incident)
            session.commit()


@router.post("/alert")
async def handle_alert(
    payload: AlertmanagerWebhook,
    background: BackgroundTasks,
    session: Session = Depends(get_session),
) -> dict[str, str | int]:
    queued = 0
    for alert in payload.alerts:
        if alert.status == "resolved":
            logger.info("alert resolved", extra={"fingerprint": alert.fingerprint})
            continue
        incident_id = upsert_incident(session, alert)
        background.add_task(investigate, incident_id)
        queued += 1

    return {"status": "accepted", "queued": queued}


@router.post("/execute")
async def execute_investigation(incident_id: str):
    # TODO: llm to check and execute the last analysis
    ...
