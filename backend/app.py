from __future__ import annotations

import io
from functools import lru_cache
from typing import Callable, Protocol

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError

from backend import config
from backend.inference import PredictionService
from backend.model_adapters import (
    EfficientNetDiseaseClassifier,
    YoloLeafDetector,
    load_solutions,
)


class PredictService(Protocol):
    def predict(self, image: Image.Image) -> dict:
        ...


@lru_cache(maxsize=1)
def build_service() -> PredictionService:
    return PredictionService(
        detector=YoloLeafDetector(config.YOLO_MODEL_PATH, config.YOLO_CONFIDENCE),
        classifier=EfficientNetDiseaseClassifier(config.EFFICIENTNET_MODEL_PATH),
        solutions=load_solutions(config.DISEASE_SOLUTIONS_PATH),
    )


def create_app(
    service_factory: Callable[[], PredictService] = build_service,
) -> FastAPI:
    app = FastAPI(title="Smart Farm AI Backend")
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

    return app


app = create_app()

