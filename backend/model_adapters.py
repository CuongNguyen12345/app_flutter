from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np
import torch
from PIL import Image
from torchvision import models, transforms
from ultralytics import YOLO

from backend.inference import Detection


def load_solutions(path: Path) -> dict[str, dict[str, str]]:
    with path.open("r", encoding="utf-8") as file:
        raw = json.load(file)
    return {str(key): dict(value) for key, value in raw.items()}


class YoloLeafDetector:
    def __init__(self, model_path: Path, confidence: float = 0.25) -> None:
        if not model_path.exists():
            raise FileNotFoundError(f"YOLO model not found: {model_path}")
        self._model = YOLO(str(model_path))
        self._confidence = confidence

    def detect(self, image: Image.Image) -> list[Detection]:
        results = self._model.predict(
            source=np.array(image.convert("RGB")),
            conf=self._confidence,
            verbose=False,
        )
        if not results:
            return []

        boxes = results[0].boxes
        if boxes is None:
            return []

        detections: list[Detection] = []
        for box in boxes:
            x1, y1, x2, y2 = box.xyxy[0].detach().cpu().tolist()
            confidence = float(box.conf[0].detach().cpu().item())
            detections.append(
                Detection(
                    box=[round(x1), round(y1), round(x2), round(y2)],
                    confidence=confidence,
                )
            )
        return detections


class EfficientNetDiseaseClassifier:
    def __init__(self, checkpoint_path: Path) -> None:
        if not checkpoint_path.exists():
            raise FileNotFoundError(f"EfficientNet checkpoint not found: {checkpoint_path}")

        self._device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        checkpoint = torch.load(
            checkpoint_path,
            map_location=self._device,
            weights_only=False,
        )
        self._class_names = list(checkpoint["class_names"])
        num_classes = int(checkpoint.get("num_classes", len(self._class_names)))

        self._model = models.efficientnet_b3(weights=None)
        in_features = self._model.classifier[1].in_features
        self._model.classifier = torch.nn.Sequential(
            torch.nn.Dropout(p=0.3, inplace=True),
            torch.nn.Linear(in_features, num_classes),
        )
        self._model.load_state_dict(checkpoint["model_state_dict"])
        self._model.to(self._device)
        self._model.eval()

        self._transform = transforms.Compose(
            [
                transforms.Resize((300, 300)),
                transforms.ToTensor(),
                transforms.Normalize(
                    mean=[0.485, 0.456, 0.406],
                    std=[0.229, 0.224, 0.225],
                ),
            ]
        )

    @torch.no_grad()
    def classify(self, image: Image.Image) -> dict[str, Any]:
        tensor = self._transform(image.convert("RGB")).unsqueeze(0).to(self._device)
        outputs = self._model(tensor)
        probabilities = torch.softmax(outputs, dim=1)
        confidence, class_index = torch.max(probabilities, dim=1)
        index = int(class_index.item())
        return {
            "class_name": self._class_names[index],
            "confidence": float(confidence.item()),
        }

