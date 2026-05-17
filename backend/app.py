from __future__ import annotations

import io
from functools import lru_cache
from typing import Any, Callable, Protocol

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError

from backend import config
from backend.camera_monitor import AutoWebcamMonitor
from backend.inference import PredictionService
from backend.model_adapters import (
    EfficientNetDiseaseClassifier,
    YoloLeafDetector,
    load_solutions,
)


class PredictService(Protocol):
    def predict(self, image: Image.Image) -> dict:
        ...


class MonitorService(Protocol):
    def start(self, camera_index: int | None = None) -> dict[str, Any]:
        ...

    def stop(self) -> dict[str, Any]:
        ...

    def status(self) -> dict[str, Any]:
        ...

    def latest(self) -> dict[str, Any]:
        ...


@lru_cache(maxsize=1)
def build_service() -> PredictionService:
    return PredictionService(
        detector=YoloLeafDetector(config.YOLO_MODEL_PATH, config.YOLO_CONFIDENCE),
        classifier=EfficientNetDiseaseClassifier(config.EFFICIENTNET_MODEL_PATH),
        solutions=load_solutions(config.DISEASE_SOLUTIONS_PATH),
        min_leaf_area_ratio=config.MIN_LEAF_AREA_RATIO,
    )


@lru_cache(maxsize=1)
def build_monitor() -> AutoWebcamMonitor:
    return AutoWebcamMonitor(prediction_service=build_service())


def create_app(
    service_factory: Callable[[], PredictService] = build_service,
    monitor_factory: Callable[[], MonitorService] = build_monitor,
) -> FastAPI:
    app = FastAPI(title="Smart Farm AI Backend")
    monitor: MonitorService | None = None

    def get_monitor() -> MonitorService:
        nonlocal monitor
        if monitor is None:
            monitor = monitor_factory()
        return monitor

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/predict")
    async def predict(file: UploadFile = File(...)) -> dict:
        try:
            contents = await file.read()
            image = Image.open(io.BytesIO(contents)).convert("RGB")
        except (UnidentifiedImageError, OSError) as exc:
            raise HTTPException(status_code=400, detail="Invalid image file") from exc

        return service_factory().predict(image)

    @app.post("/monitor/start")
    def start_monitor(camera_index: int | None = None) -> dict[str, Any]:
        return get_monitor().start(camera_index=camera_index)

    @app.post("/monitor/stop")
    def stop_monitor() -> dict[str, Any]:
        return get_monitor().stop()

    @app.get("/monitor/status")
    def monitor_status() -> dict[str, Any]:
        return get_monitor().status()

    @app.get("/monitor/latest")
    def monitor_latest() -> dict[str, Any]:
        return get_monitor().latest()

    return app


app = create_app()
