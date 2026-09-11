from pathlib import Path

from agents import Agent, ModelSettings
from schemas.alert import AlertItem

PROMPT_PATH = Path(__file__).parent / ".." / "prompts" / "linux_admin.md"


def load_instructions(ctx, agent) -> str:
    return PROMPT_PATH.read_text(encoding="utf-8")


linux_admin_agent = Agent(
    name="Linux Admin",
    instructions=(
        "You are a Senior Linux System Administrator with 15+ years of experience operating production Linux servers (Debian/Ubuntu, RHEL-family). "
        "You are invoked automatically when an alert fires for a failed or degraded service on one of the managed hosts. "
        "Your job is to perform the initial troubleshooting and hand a human a clear, evidence-based report."
    ),
    output_type=AlertItem,
    model_settings=ModelSettings(temperature=0),
    model="gpt-4o-mini",
)
