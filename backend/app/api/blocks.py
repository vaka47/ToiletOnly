from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import and_, delete, or_, select
from ..db import get_db
from ..models import Block, VideoFollow
from ..schemas import BlockRequest, BlockOut
from ..security import get_current_user_id

router = APIRouter(prefix="/blocks", tags=["blocks"])


@router.post("/", response_model=BlockOut)
async def block_user(
    payload: BlockRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    block = Block(blocker_id=user_id, blocked_user_id=payload.blocked_user_id)
    db.add(block)
    await db.execute(
        delete(VideoFollow).where(
            or_(
                and_(VideoFollow.follower_id == user_id, VideoFollow.target_user_id == payload.blocked_user_id),
                and_(VideoFollow.follower_id == payload.blocked_user_id, VideoFollow.target_user_id == user_id),
            )
        )
    )
    await db.commit()
    return BlockOut(blocker_id=str(user_id), blocked_user_id=payload.blocked_user_id)


@router.get("/", response_model=list[BlockOut])
async def list_blocks(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = await db.execute(select(Block).where(Block.blocker_id == user_id))
    items = result.scalars().all()
    return [
        BlockOut(blocker_id=str(item.blocker_id), blocked_user_id=str(item.blocked_user_id))
        for item in items
    ]


@router.delete("/{blocked_user_id}")
async def unblock_user(
    blocked_user_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = await db.execute(
        select(Block).where(
            Block.blocker_id == user_id,
            Block.blocked_user_id == blocked_user_id,
        )
    )
    block = result.scalar_one_or_none()
    if not block:
        raise HTTPException(status_code=404, detail="Block not found")
    await db.delete(block)
    await db.commit()
    return {"status": "ok"}
