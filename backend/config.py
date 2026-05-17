from __future__ import annotations

import os
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parent


YOLO_MODEL_PATH = Path(
    os.getenv("YOLO_MODEL_PATH", PROJECT_ROOT / "backend" / "models" / "best.pt")
)
EFFICIENTNET_MODEL_PATH = Path(
    os.getenv(
        "EFFICIENTNET_MODEL_PATH",
        PROJECT_ROOT / "backend" / "models" / "efficientnetb3.pth",
    )
)
DISEASE_SOLUTIONS_PATH = Path(
    os.getenv(
        "DISEASE_SOLUTIONS_PATH",
        PROJECT_ROOT / "assets" / "data" / "disease_solutions.json",
    )
)

YOLO_CONFIDENCE = float(os.getenv("YOLO_CONFIDENCE", "0.25"))
MIN_LEAF_AREA_RATIO = float(os.getenv("MIN_LEAF_AREA_RATIO", "0.08"))
