import unittest
import threading

from PIL import Image

from backend.camera_monitor import AutoWebcamMonitor, FrameChangeDetector


class FakePredictionService:
    def __init__(self):
        self.calls = 0

    def predict(self, image):
        self.calls += 1
        return {
            "image": {"width": image.width, "height": image.height},
            "detections": [],
            "summary": {"has_disease": False, "leaf_count": 0},
        }


class FakeFrameSource:
    def __init__(self, frames):
        self.frames = list(frames)
        self.opened = False
        self.released = False

    def open(self, camera_index):
        self.opened = True

    def read(self):
        if not self.frames:
            return None
        return self.frames.pop(0)

    def release(self):
        self.released = True


class FakeCapture:
    def __init__(self, opened):
        self._opened = opened
        self.released = False

    def isOpened(self):
        return self._opened

    def release(self):
        self.released = True


class FakeCv2:
    CAP_DSHOW = 700
    CAP_MSMF = 1400

    def __init__(self):
        self.calls = []
        self.captures = [FakeCapture(False), FakeCapture(True)]

    def VideoCapture(self, camera_index, backend=None):
        self.calls.append((camera_index, backend))
        return self.captures.pop(0)


class FrameChangeDetectorTest(unittest.TestCase):
    def test_first_frame_triggers_analysis(self):
        detector = FrameChangeDetector(change_threshold=8.0, force_interval_seconds=10.0)
        frame = Image.new("RGB", (20, 20), color=(10, 10, 10))

        self.assertTrue(detector.should_analyze(frame, now=1.0))

    def test_unchanged_frame_before_interval_is_skipped(self):
        detector = FrameChangeDetector(change_threshold=8.0, force_interval_seconds=10.0)
        frame = Image.new("RGB", (20, 20), color=(10, 10, 10))

        detector.should_analyze(frame, now=1.0)

        self.assertFalse(detector.should_analyze(frame, now=2.0))

    def test_changed_frame_triggers_analysis(self):
        detector = FrameChangeDetector(change_threshold=8.0, force_interval_seconds=10.0)
        first = Image.new("RGB", (20, 20), color=(10, 10, 10))
        changed = Image.new("RGB", (20, 20), color=(80, 80, 80))

        detector.should_analyze(first, now=1.0)

        self.assertTrue(detector.should_analyze(changed, now=2.0))


class OpenCvWebcamSourceTest(unittest.TestCase):
    def test_open_tries_windows_capture_backends_before_failing(self):
        from backend.camera_monitor import OpenCvWebcamSource

        fake_cv2 = FakeCv2()
        source = OpenCvWebcamSource(cv2_module=fake_cv2)

        source.open(camera_index=0)

        self.assertEqual(fake_cv2.calls, [(0, 700), (0, 1400)])


class AutoWebcamMonitorTest(unittest.TestCase):
    def test_start_returns_status_without_deadlocking(self):
        prediction_service = FakePredictionService()
        frame = Image.new("RGB", (32, 24), color=(20, 90, 30))
        frame_source = FakeFrameSource([frame])
        monitor = AutoWebcamMonitor(
            prediction_service=prediction_service,
            frame_source=frame_source,
            detector=FrameChangeDetector(change_threshold=8.0, force_interval_seconds=10.0),
            capture_interval_seconds=0.01,
        )
        result = {}

        thread = threading.Thread(
            target=lambda: result.update(status=monitor.start()),
            daemon=True,
        )
        thread.start()
        thread.join(timeout=1)

        self.assertFalse(thread.is_alive(), "monitor.start() deadlocked")
        self.assertIn("status", result)
        self.assertTrue(frame_source.opened)
        monitor.stop()

    def test_scan_once_updates_status_and_latest_result(self):
        prediction_service = FakePredictionService()
        frame = Image.new("RGB", (32, 24), color=(20, 90, 30))
        frame_source = FakeFrameSource([frame])
        monitor = AutoWebcamMonitor(
            prediction_service=prediction_service,
            frame_source=frame_source,
            detector=FrameChangeDetector(change_threshold=8.0, force_interval_seconds=10.0),
        )

        monitor.scan_once(now=1.0)

        status = monitor.status()
        self.assertEqual(status["frame_count"], 1)
        self.assertEqual(status["analysis_count"], 1)
        self.assertIsNone(status["latest_error"])
        self.assertEqual(monitor.latest()["result"]["image"], {"width": 32, "height": 24})
        self.assertEqual(prediction_service.calls, 1)


if __name__ == "__main__":
    unittest.main()
