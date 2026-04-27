#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import shutil
import subprocess
from pathlib import Path


VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}


def iter_videos(path: Path):
    if path.is_file():
        if path.suffix.lower() in VIDEO_EXTENSIONS:
            yield path
        return

    for candidate in sorted(path.rglob("*")):
        if candidate.is_file() and candidate.suffix.lower() in VIDEO_EXTENSIONS:
            yield candidate


def sanitize_stem(path: Path) -> str:
    return "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in path.stem)


def extract_with_cv2(video_path: Path, out_dir: Path, prefix: str, every_seconds: float) -> int:
    try:
        import cv2  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "ffmpeg is not installed and OpenCV is missing. Install one of them and rerun. "
            "For Python fallback: python3 -m pip install opencv-python-headless"
        ) from exc

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise SystemExit(f"Failed to open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS)
    if not fps or fps <= 0:
        fps = 30.0
    frame_step = max(1, int(math.floor(fps * every_seconds)))

    frame_index = 0
    saved = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame_index % frame_step == 0:
            saved += 1
            out_path = out_dir / f"{prefix}_{saved:06d}.jpg"
            cv2.imwrite(str(out_path), frame, [int(cv2.IMWRITE_JPEG_QUALITY), 95])
        frame_index += 1

    cap.release()
    return saved


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract JPEG frames from videos for hard-negative collection.")
    parser.add_argument(
        "--src",
        action="append",
        required=True,
        help="Source video file or directory. Repeatable.",
    )
    parser.add_argument("--out", required=True, help="Output directory for extracted frames.")
    parser.add_argument(
        "--every-seconds",
        type=float,
        default=2.0,
        help="Extract one frame every N seconds.",
    )
    args = parser.parse_args()

    if args.every_seconds <= 0:
        raise SystemExit("--every-seconds must be > 0")
    ffmpeg = shutil.which("ffmpeg")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    videos: list[Path] = []
    for src in args.src:
        src_path = Path(src)
        if not src_path.exists():
            raise SystemExit(f"Source path does not exist: {src_path}")
        videos.extend(iter_videos(src_path))

    if not videos:
        raise SystemExit("No videos found")

    extracted = 0
    for index, video_path in enumerate(videos, start=1):
        stem = sanitize_stem(video_path)
        prefix = f"{index:03d}_{stem}"
        if ffmpeg:
            pattern = out_dir / f"{prefix}_%06d.jpg"
            command = [
                ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-i",
                str(video_path),
                "-vf",
                f"fps=1/{args.every_seconds}",
                "-q:v",
                "2",
                str(pattern),
            ]
            subprocess.run(command, check=True)
        else:
            extract_with_cv2(video_path, out_dir, prefix, args.every_seconds)
        extracted += 1
        print(f"[{extracted}/{len(videos)}] extracted frames from {video_path}")

    print(f"Done. Frames written to {out_dir.resolve()}")


if __name__ == "__main__":
    main()
