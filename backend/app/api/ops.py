from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_db
from ..models import Report, User
from ..schemas import OpsSummaryOut, ReportModerationOut, ReportModerationUpdate
from ..security import get_current_user_id
from ..services.analytics import build_ops_summary

router = APIRouter(prefix="/ops", tags=["ops"])


@router.get("/summary", response_model=OpsSummaryOut)
async def ops_summary(
    db: AsyncSession = Depends(get_db),
    _: str = Depends(get_current_user_id),
    window_days: int = Query(default=30, ge=1, le=365),
):
    return await build_ops_summary(db, window_days=window_days)


@router.get("/reports", response_model=list[ReportModerationOut])
async def list_reports(
    db: AsyncSession = Depends(get_db),
    _: str = Depends(get_current_user_id),
    limit: int = Query(default=100, ge=1, le=300),
    status: Optional[str] = Query(default=None),
):
    query = select(Report).order_by(Report.created_at.desc()).limit(limit)
    if status:
        query = query.where(Report.status == status)
    rows = (await db.execute(query)).scalars().all()
    if not rows:
        return []

    user_ids = {reporter_id for item in rows for reporter_id in [item.reporter_id, item.target_user_id] if reporter_id}
    users = (
        await db.execute(select(User).where(User.id.in_(user_ids)))
    ).scalars().all()
    user_map = {str(user.id): user for user in users}

    return [
        ReportModerationOut(
            id=str(item.id),
            reporter_user_id=str(item.reporter_id),
            reporter_display_name=user_map.get(str(item.reporter_id)).display_name if user_map.get(str(item.reporter_id)) else "Unknown",
            target_user_id=str(item.target_user_id),
            target_display_name=user_map.get(str(item.target_user_id)).display_name if user_map.get(str(item.target_user_id)) else "Unknown",
            report_type=item.report_type,
            object_id=item.object_id,
            reason=item.reason,
            status=item.status,
            reviewed_at=item.reviewed_at.isoformat() if item.reviewed_at else None,
            reviewed_note=item.reviewed_note,
            created_at=item.created_at.isoformat(),
        )
        for item in rows
    ]


@router.patch("/reports/{report_id}", response_model=ReportModerationOut)
async def update_report(
    report_id: str,
    payload: ReportModerationUpdate,
    db: AsyncSession = Depends(get_db),
    reviewer_user_id: str = Depends(get_current_user_id),
):
    report = (await db.execute(select(Report).where(Report.id == report_id))).scalar_one_or_none()
    if report is None:
        raise HTTPException(status_code=404, detail="report_not_found")

    report.status = payload.status
    report.reviewed_note = payload.reviewed_note.strip() if payload.reviewed_note else None
    report.reviewed_at = datetime.now(timezone.utc)
    report.reviewer_user_id = reviewer_user_id
    db.add(report)
    await db.commit()

    users = (
        await db.execute(select(User).where(User.id.in_([report.reporter_id, report.target_user_id])))
    ).scalars().all()
    user_map = {str(user.id): user for user in users}
    return ReportModerationOut(
        id=str(report.id),
        reporter_user_id=str(report.reporter_id),
        reporter_display_name=user_map.get(str(report.reporter_id)).display_name if user_map.get(str(report.reporter_id)) else "Unknown",
        target_user_id=str(report.target_user_id),
        target_display_name=user_map.get(str(report.target_user_id)).display_name if user_map.get(str(report.target_user_id)) else "Unknown",
        report_type=report.report_type,
        object_id=report.object_id,
        reason=report.reason,
        status=report.status,
        reviewed_at=report.reviewed_at.isoformat() if report.reviewed_at else None,
        reviewed_note=report.reviewed_note,
        created_at=report.created_at.isoformat(),
    )
