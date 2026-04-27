import argparse
import os
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Download a Roboflow dataset in YOLOv8 format.")
    parser.add_argument("--workspace", required=True, help="Roboflow workspace name")
    parser.add_argument("--project", required=True, help="Roboflow project slug")
    parser.add_argument("--version", required=True, type=int, help="Roboflow dataset version")
    parser.add_argument("--out", default="/Users/vaka47/Dev/Приложение в туалете/ml/data/roboflow", help="Output directory")
    return parser.parse_args()


def main():
    args = parse_args()

    api_key = os.environ.get("ROBOFLOW_API_KEY")
    if not api_key:
        raise SystemExit("ROBOFLOW_API_KEY is not set")

    try:
        from roboflow import Roboflow
    except Exception as exc:
        raise SystemExit(
            "roboflow package is required. Install with: python3 -m pip install -r /Users/vaka47/Dev/Приложение\ в\ туалете/ml/scripts/requirements.txt"
        ) from exc

    rf = Roboflow(api_key=api_key)
    project = rf.workspace(args.workspace).project(args.project)
    dataset = project.version(args.version).download("yolov8", location=str(Path(args.out)))

    print(f"Downloaded Roboflow dataset to {dataset.location}")


if __name__ == "__main__":
    main()
