import unittest

from PIL import Image

from backend.inference import Detection, PredictionService


class FakeLeafDetector:
    def detect(self, image):
        return [
            Detection(box=[10, 20, 70, 90], confidence=0.91),
            Detection(box=[80, 30, 130, 100], confidence=0.76),
        ]


class FakeDiseaseClassifier:
    def classify(self, image):
        return {
            "class_name": "Lemon___Citrus_canker",
            "confidence": 0.87,
        }


class PredictionServiceTest(unittest.TestCase):
    def test_predict_combines_leaf_boxes_disease_and_solution(self):
        image = Image.new("RGB", (160, 120), color=(20, 90, 30))
        solutions = {
            "Lemon___Citrus_canker": {
                "name_vi": "Chanh - loet vi khuan/canker",
                "status": "disease",
                "solution": "Cat bo la benh va tranh tuoi phun len la.",
            }
        }
        service = PredictionService(
            detector=FakeLeafDetector(),
            classifier=FakeDiseaseClassifier(),
            solutions=solutions,
        )

        result = service.predict(image)

        self.assertEqual(result["image"]["width"], 160)
        self.assertEqual(result["image"]["height"], 120)
        self.assertEqual(len(result["detections"]), 2)
        self.assertEqual(result["detections"][0]["box"], [10, 20, 70, 90])
        self.assertEqual(result["detections"][0]["leaf_confidence"], 0.91)
        self.assertEqual(result["detections"][0]["disease"], "Lemon___Citrus_canker")
        self.assertEqual(result["detections"][0]["disease_name_vi"], "Chanh - loet vi khuan/canker")
        self.assertEqual(result["detections"][0]["disease_confidence"], 0.87)
        self.assertEqual(
            result["detections"][0]["solution"],
            "Cat bo la benh va tranh tuoi phun len la.",
        )
        self.assertTrue(result["summary"]["has_disease"])
        self.assertEqual(result["summary"]["disease"], "Lemon___Citrus_canker")
        self.assertEqual(result["summary"]["leaf_count"], 2)

    def test_predict_reports_no_leaf_when_detector_returns_empty(self):
        class EmptyLeafDetector:
            def detect(self, image):
                return []

        image = Image.new("RGB", (80, 60), color=(0, 0, 0))
        service = PredictionService(
            detector=EmptyLeafDetector(),
            classifier=FakeDiseaseClassifier(),
            solutions={},
        )

        result = service.predict(image)

        self.assertEqual(result["detections"], [])
        self.assertFalse(result["summary"]["has_disease"])
        self.assertEqual(result["summary"]["leaf_count"], 0)
        self.assertEqual(result["summary"]["message"], "Khong phat hien la cay trong anh.")


if __name__ == "__main__":
    unittest.main()
