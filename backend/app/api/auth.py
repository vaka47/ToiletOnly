from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from ..db import get_db
from ..models import User
from ..schemas import AuthRequest, AuthResponse
from ..security import create_access_token

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/apple", response_model=AuthResponse)
async def auth_apple(payload: AuthRequest, db: AsyncSession = Depends(get_db)):
    # TODO: Verify Apple identity token properly.
    # For now, treat id_token as apple_sub in dev.
    apple_sub = payload.id_token
    if not apple_sub:
        raise HTTPException(status_code=400, detail="missing_token")

    result = await db.execute(select(User).where(User.apple_sub == apple_sub))
    user = result.scalar_one_or_none()
    if user is None:
        user = User(apple_sub=apple_sub, age=18, gender="unknown", display_name="ToiletUser")
        db.add(user)
        await db.commit()
        await db.refresh(user)

    token = create_access_token(str(user.id))
    return AuthResponse(access_token=token, user_id=str(user.id))
