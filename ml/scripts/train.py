import argparse


def parse_args():
    parser = argparse.ArgumentParser(description="Train toilet detector (YOLOv8).")
    parser.add_argument("--data", required=True, help="Path to dataset yaml.")
    parser.add_argument("--model", default="yolov8n.pt", help="Base model weights.")
    parser.add_argument("--epochs", type=int, default=80, help="Training epochs.")
    parser.add_argument("--imgsz", type=int, default=640, help="Image size.")
    parser.add_argument("--batch", type=int, default=16, help="Batch size.")
    parser.add_argument("--name", default="train", help="Run name.")
    parser.add_argument("--device", default=None, help="Device, e.g. mps or 0")
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume training from last checkpoint for the run.",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    try:
        from ultralytics import YOLO
    except Exception as exc:
        raise SystemExit(
            "ultralytics is required. Install with: python3 -m pip install -r ml/scripts/requirements.txt"
        ) from exc

    model = YOLO(args.model)
    model.train(
        data=args.data,
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        name=args.name,
        device=args.device,
        resume=args.resume,
    )


if __name__ == "__main__":
    main()
