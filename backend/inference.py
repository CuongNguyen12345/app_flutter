from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Protocol

from PIL import Image


@dataclass(frozen=True)
class Detection:
    box: list[int]
    confidence: float


class LeafDetector(Protocol):
    def detect(self, image: Image.Image) -> list[Detection]:
        ...


class DiseaseClassifier(Protocol):
    def classify(self, image: Image.Image) -> dict[str, Any]:
        ...


class PredictionService:
    def __init__(
        self,
        detector: LeafDetector,
        classifier: DiseaseClassifier,
        solutions: Mapping[str, Mapping[str, str]],
        min_leaf_area_ratio: float = 0.08,
    ) -> None:
        self._detector = detector
        self._classifier = classifier
        self._solutions = solutions
        self._min_leaf_area_ratio = min_leaf_area_ratio

    def predict(self, image: Image.Image) -> dict[str, Any]:
        rgb_image = image.convert("RGB")
        detections = self._filter_detections(
            self._detector.detect(rgb_image),
            rgb_image.width,
            rgb_image.height,
        )

        if not detections:
            return {
                "image": {"width": rgb_image.width, "height": rgb_image.height},
                "detections": [],
                "summary": {
                    "has_disease": False,
                    "leaf_count": 0,
                    "message": "Khong phat hien la cay trong anh.",
                },
            }

        prediction_items = [
            self._predict_leaf(rgb_image, detection) for detection in detections
        ]
        primary = max(
            prediction_items,
            key=lambda item: float(item.get("leaf_area_ratio", 0.0)),
        )

        return {
            "image": {"width": rgb_image.width, "height": rgb_image.height},
            "detections": prediction_items,
            "summary": {
                "has_disease": primary.get("status") != "healthy",
                "leaf_count": len(prediction_items),
                "disease": primary["disease"],
                "disease_name_vi": primary["disease_name_vi"],
                "disease_confidence": primary["disease_confidence"],
                "solution": primary["solution"],
            },
        }

    def _predict_leaf(self, image: Image.Image, detection: Detection) -> dict[str, Any]:
        x1, y1, x2, y2 = self._clamp_box(detection.box, image.width, image.height)
        leaf_crop = image.crop((x1, y1, x2, y2))
        disease = self._classifier.classify(leaf_crop)
        class_name = str(disease["class_name"])
        solution = self._solutions.get(class_name, {})

        return {
            "box": [x1, y1, x2, y2],
            "leaf_area_ratio": round(
                ((x2 - x1) * (y2 - y1)) / (image.width * image.height),
                4,
            ),
            "leaf_confidence": round(float(detection.confidence), 4),
            "disease": class_name,
            "disease_name_vi": solution.get("name_vi", class_name),
            "disease_confidence": round(float(disease["confidence"]), 4),
            "status": solution.get("status", "unknown"),
            "solution": solution.get(
                "solution",
                "Chua co huong xu ly cho lop benh nay.",
            ),
        }

    def _filter_detections(
        self,
        detections: list[Detection],
        width: int,
        height: int,
    ) -> list[Detection]:
        if self._min_leaf_area_ratio <= 0:
            return detections

        image_area = width * height
        filtered = [
            detection
            for detection in detections
            if self._box_area_ratio(detection.box, image_area) >= self._min_leaf_area_ratio
        ]
        return filtered

    @staticmethod
    def _box_area_ratio(box: list[int], image_area: int) -> float:
        x1, y1, x2, y2 = box
        return max(0, x2 - x1) * max(0, y2 - y1) / image_area

    @staticmethod
    def _clamp_box(box: list[int], width: int, height: int) -> list[int]:
        x1, y1, x2, y2 = box
        x1 = max(0, min(width - 1, int(round(x1))))
        y1 = max(0, min(height - 1, int(round(y1))))
        x2 = max(x1 + 1, min(width, int(round(x2))))
        y2 = max(y1 + 1, min(height, int(round(y2))))
        return [x1, y1, x2, y2]
