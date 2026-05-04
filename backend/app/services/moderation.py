from __future__ import annotations

import os
import tempfile
from typing import Iterable, Optional

try:
    import cv2
except Exception:
    cv2 = None

try:
    from nudenet import NudeClassifier
except Exception:
    NudeClassifier = None


SKIN_RATIO_THRESHOLD = 0.35
FACE_MIN_SIZE = (60, 60)

_FACE_CASCADE = None
_NUDE_CLASSIFIER = None


def _get_face_cascade():
    global _FACE_CASCADE
    if cv2 is None:
        return None
    if _FACE_CASCADE is None:
        path = os.path.join(cv2.data.haarcascades, "haarcascade_frontalface_default.xml")
        _FACE_CASCADE = cv2.CascadeClassifier(path)
    return _FACE_CASCADE


def _get_nude_classifier() -> Optional["NudeClassifier"]:
    global _NUDE_CLASSIFIER
    if _NUDE_CLASSIFIER is not None:
        return _NUDE_CLASSIFIER
    if NudeClassifier is None:
        return None
    try:
        _NUDE_CLASSIFIER = NudeClassifier()
        return _NUDE_CLASSIFIER
    except Exception:
        _NUDE_CLASSIFIER = None
        return None


def _nudenet_score_from_path(path: str) -> Optional[float]:
    classifier = _get_nude_classifier()
    if classifier is None:
        return None
    try:
        result = classifier.classify(path)
    except Exception:
        return None
    scores = result.get(path, {}) if isinstance(result, dict) else {}
    if not scores:
        return None
    return max(
        float(scores.get("porn", 0)),
        float(scores.get("hentai", 0)),
        float(scores.get("sexy", 0)),
    )


def _nudenet_score_from_frame(frame) -> Optional[float]:
    classifier = _get_nude_classifier()
    if classifier is None or cv2 is None:
        return None
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=True) as tmp:
        try:
            cv2.imwrite(tmp.name, frame)
        except Exception:
            return None
        return _nudenet_score_from_path(tmp.name)


def _count_faces(image) -> int:
    if image is None or cv2 is None:
        return 0
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    cascade = _get_face_cascade()
    if cascade is None:
        return 0
    faces = cascade.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=FACE_MIN_SIZE,
    )
    return len(faces)


def _skin_ratio_bgr(image) -> float:
    if image is None or cv2 is None:
        return 0.0
    h, w = image.shape[:2]
    if h == 0 or w == 0:
        return 0.0
    ycrcb = cv2.cvtColor(image, cv2.COLOR_BGR2YCrCb)
    lower = (0, 133, 77)
    upper = (255, 173, 127)
    mask = cv2.inRange(ycrcb, lower, upper)
    skin_pixels = cv2.countNonZero(mask)
    total = h * w
    return skin_pixels / float(total)


def _sample_video_frames(path: str, count: int = 5) -> Iterable:
    if cv2 is None:
        return []
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        return []
    length = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if length <= 0:
        length = 30
    indices = [0, length // 4, length // 2, (3 * length) // 4, max(0, length - 1)]
    frames = []
    for idx in indices[:count]:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ret, frame = cap.read()
        if ret:
            frames.append(frame)
    cap.release()
    return frames


def is_nsfw_image(path: str, require_face: bool = False) -> bool:
    image = cv2.imread(path) if cv2 is not None else None
    if image is None:
        ml_score = _nudenet_score_from_path(path)
        return bool(ml_score is not None and ml_score >= 0.5)
    if require_face and _count_faces(image) == 0:
        return True
    ml_score = _nudenet_score_from_path(path)
    if ml_score is not None and ml_score >= 0.5:
        return True
    return _skin_ratio_bgr(image) >= SKIN_RATIO_THRESHOLD


def is_nsfw_video(path: str, require_face: bool = False) -> bool:
    frames = _sample_video_frames(path)
    if not frames:
        return False
    face_seen = False
    for frame in frames:
        ml_score = _nudenet_score_from_frame(frame)
        if ml_score is not None and ml_score >= 0.5:
            return True
        if _skin_ratio_bgr(frame) >= SKIN_RATIO_THRESHOLD:
            return True
        if require_face and _count_faces(frame) > 0:
            face_seen = True
    if require_face and not face_seen:
        return True
    return False


def has_face_image(path: str) -> bool:
    if cv2 is None:
        return True
    image = cv2.imread(path)
    if image is None:
        return False
    return _count_faces(image) > 0


def has_face_video(path: str) -> bool:
    if cv2 is None:
        return True
    frames = _sample_video_frames(path)
    for frame in frames:
        if _count_faces(frame) > 0:
            return True
    return False


def is_nsfw(path: str, require_face: bool = False) -> bool:
    _, ext = os.path.splitext(path.lower())
    ext = ext.replace(".", "")

    if ext in {"jpg", "jpeg", "png", "webp"}:
        return is_nsfw_image(path, require_face=require_face)

    if ext in {"mov", "mp4", "m4v"}:
        return is_nsfw_video(path, require_face=require_face)

    return False
