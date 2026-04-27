from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from ..db import get_db
from ..models import DeviceToken
from ..schemas import DeviceTokenRequest
from ..security import get_current_user_id

router = APIRouter(prefix="/devices", tags=["devices"])


@router.post("/register")
async def register_device(
    payload: DeviceTokenRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = await db.execute(select(DeviceToken).where(DeviceToken.token == payload.token))
    existing = result.scalar_one_or_none()
    if existing:
        existing.user_id = user_id
        existing.platform = payload.platform
        await db.commit()
        return {"status": "ok"}

    device = DeviceToken(user_id=user_id, token=payload.token, platform=payload.platform)
    db.add(device)
    await db.commit()
    return {"status": "ok"}
