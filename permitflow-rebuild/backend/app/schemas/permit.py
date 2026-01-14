from pydantic import BaseModel
from datetime import datetime

class PermitCreate(BaseModel):
    county_id: int
    type: str

class Permit(PermitCreate):
    id: str
    user_id: str
    status: str
    current_step: str
    submitted_at: datetime
    updated_at: datetime
    offline_submission: bool
