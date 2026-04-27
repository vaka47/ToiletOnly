#!/usr/bin/env python3
from __future__ import annotations

import argparse
import random
from pathlib import Path


def read_lines(path: Path) -> list[str]:
    return [line.strip() for line in path.read_text().splitlines() if line.strip()]


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Move a portion of Objects365 samples from train into val/test lists."
    )
    parser.add_argument("--in-dir", required=True, help="Input dir with train/val/test .txt lists")
    parser.add_argument("--out-dir", required=True, help="Output dir for rebalanced lists")
    parser.add_argument("--o365-marker", default="objects365_toilet_full", help="Path marker to detect Objects365 samples")
    parser.add_argument("--val-ratio", type=float, default=0.1, help="Fraction of O365 train samples to move to val")
    parser.add_argument("--test-ratio", type=float, default=0.1, help="Fraction of O365 train samples to move to test")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    args = parser.parse_args()

    in_dir = Path(args.in_dir)
    out_dir = Path(args.out_dir)
    marker = args.o365_marker

    train = read_lines(in_dir / "train.txt")
    val = read_lines(in_dir / "val.txt")
    test = read_lines(in_dir / "test.txt")

    o365_train = [x for x in train if marker in x]
    non_o365_train = [x for x in train if marker not in x]

    rnd = random.Random(args.seed)
    rnd.shuffle(o365_train)

    total = len(o365_train)
    take_val = int(total * args.val_ratio)
    take_test = int(total * args.test_ratio)
    moved_val = o365_train[:take_val]
    moved_test = o365_train[take_val : take_val + take_test]
    keep_train = o365_train[take_val + take_test :]

    new_train = non_o365_train + keep_train
    new_val = val + moved_val
    new_test = test + moved_test

    # Stable output order for reproducibility.
    new_train.sort()
    new_val.sort()
    new_test.sort()

    write_lines(out_dir / "train.txt", new_train)
    write_lines(out_dir / "val.txt", new_val)
    write_lines(out_dir / "test.txt", new_test)

    print(f"Moved O365 to val: {len(moved_val)}")
    print(f"Moved O365 to test: {len(moved_test)}")
    print(f"Train total: {len(new_train)}")
    print(f"Val total: {len(new_val)}")
    print(f"Test total: {len(new_test)}")


if __name__ == "__main__":
    main()
