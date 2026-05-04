import os
import uuid
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, Query
from fastapi.responses import JSONResponse
from ..security import get_current_user_id
from ..config import settings
from ..services.moderation import is_nsfw, has_face_image, has_face_video

router = APIRouter(prefix="/media", tags=["media"])
CHUNK_SIZE = 1024 * 1024


@router.post("/upload")
async def upload_media(
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
    purpose: str = Query("generic"),
):
    os.makedirs(settings.media_storage_path, exist_ok=True)
    ext = os.path.splitext(file.filename)[1] if file.filename else ""
    name = f"{user_id}_{uuid.uuid4().hex}{ext}"
    path = os.path.join(settings.media_storage_path, name)
    try:
        with open(path, "wb") as f:
            while True:
                chunk = await file.read(CHUNK_SIZE)
                if not chunk:
                    break
                f.write(chunk)
    finally:
        await file.close()
    try:
        require_face = purpose in {"toilet_selfie", "profile_photo", "session_video"}
        _, ext = os.path.splitext(path.lower())
        ext = ext.replace(".", "")
        if require_face:
            if ext in {"jpg", "jpeg", "png", "webp"} and not has_face_image(path):
                os.remove(path)
                raise HTTPException(status_code=400, detail="face_required")
            if ext in {"mov", "mp4", "m4v"} and not has_face_video(path):
                os.remove(path)
                raise HTTPException(status_code=400, detail="face_required")
        if is_nsfw(path, require_face=require_face):
            os.remove(path)
            raise HTTPException(status_code=400, detail="nsfw_detected")
    except HTTPException:
        raise
    except Exception:
        pass
    return JSONResponse({"asset_url": f"{settings.media_public_url}/{name}"})


@router.post("/presign")
async def presign_upload(user_id: str = Depends(get_current_user_id)):
    return {"upload_url": "", "asset_url": ""}
