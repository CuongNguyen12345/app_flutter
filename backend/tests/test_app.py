import io
import unittest

from fastapi.testclient import TestClient
from PIL import Image

from backend.app import create_app


class FakePredictionService:
    def predict(self, image):
        return {
            "image": {"width": image.width, "height": image.height},
            "detections": [
                {
                    "box": [1, 2, 20, 30],
                    "leaf_confidence": 0.9,
                    "disease": "Lemon___healthy",
                    "disease_name_vi": "Chanh - khoe manh",
                    "disease_confidence": 0.8,
                    "status": "healthy",
                    "solution": "Tiep tuc cham soc on dinh.",
                }
            ],
            "summary": {
                "has_disease": False,
                "leaf_count": 1,
                "disease": "Lemon___healthy",
                "disease_name_vi": "Chanh - khoe manh",
                "disease_confidence": 0.8,
                "solution": "Tiep tuc cham soc on dinh.",
            },
        }


class AppTest(unittest.TestCase):
    def test_predict_accepts_image_upload(self):
        app = create_app(service_factory=lambda: FakePredictionService())
        client = TestClient(app)
        image = Image.new("RGB", (40, 32), color=(10, 120, 20))
        payload = io.BytesIO()
        image.save(payload, format="PNG")
        payload.seek(0)

        response = client.post(
            "/predict",
            files={"file": ("leaf.png", payload, "image/png")},
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["image"], {"width": 40, "height": 32})
        self.assertEqual(data["detections"][0]["disease"], "Lemon___healthy")
        self.assertFalse(data["summary"]["has_disease"])

    def test_health_returns_ready_status(self):
        app = create_app(service_factory=lambda: FakePredictionService())
        client = TestClient(app)

        response = client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})


if __name__ == "__main__":
    unittest.main()
