import json
import os
import uuid
from datetime import datetime
from zoneinfo import ZoneInfo

from db import get_session
from dotenv import load_dotenv
from fastapi import APIRouter, Depends
from models.incident import Incident, IncidentAnalysis
from schemas.alert import AlertmanagerWebhook
from sqlmodel import Session, select

load_dotenv()

TIME_ZONE = ZoneInfo(os.environ["TIME_ZONE"])

router = APIRouter()


@router.post("/execute")
async def execute_investigation(incident_id: str):
    # TODO(tonytech83): llm to check and execute the last analysis
    pass


@router.post("/alert")
async def handle_alert(
    payload: AlertmanagerWebhook,
    session: Session = Depends(get_session),
) -> dict[str, str]:
    alert_data = payload.alerts[0]

    fingerprint = alert_data.fingerprint
    status = alert_data.status
    hostname = alert_data.labels.get("host", "unknown")
    ip_address = alert_data.labels.get("ip", "unknown")

    print("=" * 80)
    if status == "resolved":
        print(
            f"*** {datetime.now(tz=TIME_ZONE)} - RESOLVED by Loki rule (check loki rule) ..."
        )
        return {"status": "ok"}

    print(
        f"*** {datetime.now(tz=TIME_ZONE)} - Alert {fingerprint} added to active alerts."
        f" Host: {hostname} | IP: {ip_address} ...",
    )

    existing = session.exec(
        select(Incident).where(Incident.fingerprint == fingerprint),
    ).first()

    if existing:
        existing.failure_count += 1
        existing.fired_at = datetime.now(tz=TIME_ZONE).isoformat()
        existing.status = "PENDING"
        session.add(existing)
        session.commit()
        incident_id = existing.incident_id
        print(f"*** {datetime.now(tz=TIME_ZONE)} - Updated existing incident ...")
    else:
        incident_id = str(uuid.uuid4())
        session.add(
            Incident(
                incident_id=incident_id,
                fingerprint=fingerprint,
                hostname=hostname,
                ip_address=ip_address,
                status="PENDING",
                fired_at=datetime.now(tz=TIME_ZONE).isoformat(),
                failure_count=1,
            )
        )
        session.commit()
        print(f"*** {datetime.now(tz=TIME_ZONE)} - Created incident ...")

    # TODO: Agent call tool to gather information of failed services based on hostname or ip_address
    failed_services = "test"

    # TODO: Is this necessary?
    if not failed_services:
        return {"status": "ok"}

    print(f"*** {datetime.now(tz=TIME_ZONE)} - Failed services:")
    try:
        [print(f"    - {s}") for s in json.loads(failed_services)]
    except json.JSONDecodeError:
        return {"status": "ok"}
    print(f"*** {datetime.now(tz=TIME_ZONE)} - Logs fetched successfully ...")

    # TODO: Agent call tool for analysis on gathered information
    msg = ...
    print(f"*** {datetime.now(tz=TIME_ZONE)} - Prepared message for LLM ...")

    # TODO: Agent call tool to prepare telegram message

    # TODO: Add new incident analysis to db
    session.add(
        IncidentAnalysis(
            id=str(uuid.uuid4()),
            incident_id=incident_id,
            created_at=datetime.now(tz=TIME_ZONE).isoformat(),
            failed_services=failed_services,
            analysis=json.dumps(msg),
        )
    )
    session.commit()
    print(f"*** {datetime.now(tz=TIME_ZONE)} - Saved LLM analysis to DB ...")

    # TODO: Agent call tool to sent telegram message

    return {"status": "processed"}
