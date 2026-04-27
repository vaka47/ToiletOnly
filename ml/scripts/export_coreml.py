import argparse
import os
import shutil
import tempfile
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Export YOLOv8 weights to Core ML.")
    parser.add_argument("--weights", required=True, help="Path to best.pt")
    parser.add_argument("--output", default="ToiletDetector.mlmodel", help="Output Core ML model file")
    parser.add_argument("--imgsz", type=int, default=640, help="Image size")
    return parser.parse_args()


def main():
    args = parse_args()

    try:
        from ultralytics import YOLO
    except Exception as exc:
        raise SystemExit(
            "ultralytics is required. Install with: python3 -m pip install -r ml/scripts/requirements.txt"
        ) from exc

    weights = Path(args.weights).expanduser().resolve()
    output = Path(args.output).expanduser().resolve()

    # Ultralytics writes the initial Core ML package next to the weights file,
    # so export from a temporary writable copy when weights live on a mounted volume.
    with tempfile.TemporaryDirectory(prefix="toiletonly_coreml_export_") as tmpdir:
        tmpdir_path = Path(tmpdir)
        export_weights = tmpdir_path / weights.name
        shutil.copy2(weights, export_weights)
        os.environ.setdefault("MPLCONFIGDIR", str(tmpdir_path / "mplconfig"))
        os.environ.setdefault("YOLO_CONFIG_DIR", str(tmpdir_path / "yolo_config"))

        model = YOLO(str(export_weights))
        results = model.export(format="coreml", imgsz=args.imgsz, simplify=True)

        exported = Path(results)

        if not exported.exists():
            print("Exported model not found. Check export output logs.")
            return

        if exported.is_dir():
            if output.suffix == ".mlmodel":
                output = output.with_suffix(".mlpackage")
            if output.exists():
                shutil.rmtree(output)
            shutil.copytree(exported, output)
            print(f"Saved Core ML model package to {output}")
        else:
            output.write_bytes(exported.read_bytes())
            print(f"Saved Core ML model to {output}")


if __name__ == "__main__":
    main()
