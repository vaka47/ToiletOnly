from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from ..db import get_db
from ..models import Report
from ..schemas import ReportRequest
from ..security import get_current_user_id

router = APIRouter(prefix="/reports", tags=["reports"])


@router.post("")
async def report_user(
    payload: ReportRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    report = Report(
        reporter_id=user_id,
        target_user_id=payload.target_user_id,
        report_type=payload.report_type,
        reason=payload.reason,
    )
    db.add(report)
    await db.commit()
    return {"status": "ok"}
