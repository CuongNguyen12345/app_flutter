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

    def test_predict_ignores_tiny_leaf_boxes_from_screen_feedback(self):
        class MixedSizeLeafDetector:
            def detect(self, image):
                return [
                    Detection(box=[10, 10, 25, 25], confidence=0.99),
                    Detection(box=[40, 20, 140, 100], confidence=0.80),
                ]

        image = Image.new("RGB", (160, 120), color=(20, 90, 30))
        service = PredictionService(
            detector=MixedSizeLeafDetector(),
            classifier=FakeDiseaseClassifier(),
            solutions={
                "Lemon___Citrus_canker": {
                    "name_vi": "Chanh - loet vi khuan/canker",
                    "status": "disease",
                    "solution": "Cat bo la benh va tranh tuoi phun len la.",
                }
            },
            min_leaf_area_ratio=0.08,
        )

        result = service.predict(image)

        self.assertEqual(len(result["detections"]), 1)
        self.assertEqual(result["detections"][0]["box"], [40, 20, 140, 100])
        self.assertEqual(result["summary"]["leaf_count"], 1)

    def test_predict_uses_largest_leaf_for_summary(self):
        class MixedSizeLeafDetector:
            def detect(self, image):
                return [
                    Detection(box=[0, 0, 40, 40], confidence=0.99),
                    Detection(box=[40, 10, 150, 110], confidence=0.80),
                ]

        class SizeAwareClassifier:
            def classify(self, image):
                if image.width < 60:
                    return {
                        "class_name": "Strawberry___Leaf_scorch",
                        "confidence": 0.99,
                    }
                return {
                    "class_name": "Lemon___Citrus_canker",
                    "confidence": 0.70,
                }

        image = Image.new("RGB", (160, 120), color=(20, 90, 30))
        service = PredictionService(
            detector=MixedSizeLeafDetector(),
            classifier=SizeAwareClassifier(),
            solutions={
                "Strawberry___Leaf_scorch": {
                    "name_vi": "Dau tay - chay la",
                    "status": "disease",
                    "solution": "Kiem tra dau tay.",
                },
                "Lemon___Citrus_canker": {
                    "name_vi": "Chanh - loet vi khuan/canker",
                    "status": "disease",
                    "solution": "Kiem tra chanh.",
                },
            },
            min_leaf_area_ratio=0.01,
        )

        result = service.predict(image)

        self.assertEqual(len(result["detections"]), 2)
        self.assertEqual(result["summary"]["disease"], "Lemon___Citrus_canker")
        self.assertEqual(result["summary"]["disease_name_vi"], "Chanh - loet vi khuan/canker")


if __name__ == "__main__":
    unittest.main()
