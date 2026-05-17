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


class FakeMonitor:
    def __init__(self):
        self.started = False
        self.stopped = False

    def start(self, camera_index=None):
        self.started = True
        return {
            "running": True,
            "analyzing": False,
            "camera_index": 0 if camera_index is None else camera_index,
            "frame_count": 0,
            "analysis_count": 0,
            "latest_error": None,
            "started_at": "2026-05-16T00:00:00+00:00",
            "last_frame_at": None,
            "last_analysis_at": None,
        }

    def stop(self):
        self.stopped = True
        return {
            "running": False,
            "analyzing": False,
            "camera_index": 0,
            "frame_count": 2,
            "analysis_count": 1,
            "latest_error": None,
            "started_at": "2026-05-16T00:00:00+00:00",
            "last_frame_at": "2026-05-16T00:00:02+00:00",
            "last_analysis_at": "2026-05-16T00:00:02+00:00",
        }

    def status(self):
        return {
            "running": self.started and not self.stopped,
            "analyzing": False,
            "camera_index": 0,
            "frame_count": 2,
            "analysis_count": 1,
            "latest_error": None,
            "started_at": "2026-05-16T00:00:00+00:00",
            "last_frame_at": "2026-05-16T00:00:02+00:00",
            "last_analysis_at": "2026-05-16T00:00:02+00:00",
        }

    def latest(self):
        return {
            "result": {
                "image": {"width": 40, "height": 32},
                "detections": [],
                "summary": {"has_disease": False, "leaf_count": 0},
            },
            "updated_at": "2026-05-16T00:00:02+00:00",
            "message": None,
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

    def test_monitor_start_returns_status(self):
        monitor = FakeMonitor()
        app = create_app(
            service_factory=lambda: FakePredictionService(),
            monitor_factory=lambda: monitor,
        )
        client = TestClient(app)

        response = client.post("/monitor/start")

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data["running"])
        self.assertTrue(monitor.started)

    def test_monitor_stop_returns_status(self):
        monitor = FakeMonitor()
        app = create_app(
            service_factory=lambda: FakePredictionService(),
            monitor_factory=lambda: monitor,
        )
        client = TestClient(app)

        response = client.post("/monitor/stop")

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertFalse(data["running"])
        self.assertTrue(monitor.stopped)

    def test_monitor_status_returns_current_status(self):
        monitor = FakeMonitor()
        app = create_app(
            service_factory=lambda: FakePredictionService(),
            monitor_factory=lambda: monitor,
        )
        client = TestClient(app)

        response = client.get("/monitor/status")

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["frame_count"], 2)
        self.assertEqual(data["analysis_count"], 1)

    def test_monitor_latest_returns_latest_prediction(self):
        monitor = FakeMonitor()
        app = create_app(
            service_factory=lambda: FakePredictionService(),
            monitor_factory=lambda: monitor,
        )
        client = TestClient(app)

        response = client.get("/monitor/latest")

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["result"]["image"], {"width": 40, "height": 32})
        self.assertIsNone(data["message"])


if __name__ == "__main__":
    unittest.main()
