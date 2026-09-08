from datetime import datetime

from pydantic import BaseModel


class Subscription(BaseModel):
    plan_code: str
    plan_name: str
    status: str
    current_period_end: datetime | None
