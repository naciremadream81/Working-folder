from fastapi import APIRouter
from app.schemas.permit import PermitCreate, Permit
from uuid import uuid4
from datetime import datetime

router = APIRouter()

permits = []

@router.post("/permits", response_model=Permit)
def create_permit(permit: PermitCreate):
    new_permit = Permit(
        id=str(uuid4()),
        user_id="demo_user",
        type=permit.type,
        county_id=permit.county_id,
        status="application",
        current_step="application",
        submitted_at=datetime.now(),
        updated_at=datetime.now(),
        offline_submission=False
    )
    permits.append(new_permit)
    return new_permit

@router.get("/permits", response_model=list[Permit])
def list_permits():
    return permits
