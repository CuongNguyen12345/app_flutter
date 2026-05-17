from __future__ import annotations

import threading
import time
from datetime import datetime, timezone
from typing import Any, Protocol

from PIL import Image, ImageChops, ImageStat


class PredictionServiceLike(Protocol):
    def predict(self, image: Image.Image) -> dict[str, Any]:
        ...


class FrameSource(Protocol):
    def open(self, camera_index: int) -> None:
        ...

    def read(self) -> Image.Image | None:
        ...

    def release(self) -> None:
        ...


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class FrameChangeDetector:
    def __init__(
        self,
        change_threshold: float = 8.0,
        force_interval_seconds: float = 5.0,
    ) -> None:
        self._change_threshold = change_threshold
        self._force_interval_seconds = force_interval_seconds
        self._previous_frame: Image.Image | None = None
        self._last_analysis_at: float | None = None

    def should_analyze(self, frame: Image.Image, now: float | None = None) -> bool:
        now = time.monotonic() if now is None else now
        comparable = frame.convert("L").resize((32, 32))
        previous = self._previous_frame
        self._previous_frame = comparable

        if previous is None:
            self._last_analysis_at = now
            return True

        if (
            self._last_analysis_at is None
            or now - self._last_analysis_at >= self._force_interval_seconds
        ):
            self._last_analysis_at = now
            return True

        difference = ImageChops.difference(previous, comparable)
        mean_difference = ImageStat.Stat(difference).mean[0]
        if mean_difference >= self._change_threshold:
            self._last_analysis_at = now
            return True

        return False


class OpenCvWebcamSource:
    def __init__(self, cv2_module: Any | None = None) -> None:
        self._cv2 = cv2_module
        self._capture = None

    def open(self, camera_index: int) -> None:
        cv2 = self._load_cv2()
        backends = [
            getattr(cv2, "CAP_DSHOW", None),
            getattr(cv2, "CAP_MSMF", None),
            None,
        ]

        for backend in backends:
            if backend is None:
                capture = cv2.VideoCapture(camera_index)
            else:
                capture = cv2.VideoCapture(camera_index, backend)

            if capture.isOpened():
                self._capture = capture
                return

            capture.release()

        self._capture = None
        raise RuntimeError(f"Khong mo duoc webcam index {camera_index}.")

    def read(self) -> Image.Image | None:
        if self._capture is None:
            return None

        cv2 = self._load_cv2()

        ok, frame = self._capture.read()
        if not ok:
            return None
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        return Image.fromarray(rgb_frame)

    def release(self) -> None:
        if self._capture is not None:
            self._capture.release()
            self._capture = None

    def _load_cv2(self) -> Any:
        if self._cv2 is None:
            import cv2

            self._cv2 = cv2
        return self._cv2


class AutoWebcamMonitor:
    def __init__(
        self,
        prediction_service: PredictionServiceLike,
        frame_source: FrameSource | None = None,
        detector: FrameChangeDetector | None = None,
        capture_interval_seconds: float = 1.0,
        camera_index: int = 0,
    ) -> None:
        self._prediction_service = prediction_service
        self._frame_source = frame_source or OpenCvWebcamSource()
        self._detector = detector or FrameChangeDetector()
        self._capture_interval_seconds = capture_interval_seconds
        self._camera_index = camera_index
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._running = False
        self._analyzing = False
        self._frame_count = 0
        self._analysis_count = 0
        self._latest_error: str | None = None
        self._latest_result: dict[str, Any] | None = None
        self._latest_result_at: str | None = None
        self._started_at: str | None = None
        self._last_frame_at: str | None = None
        self._last_analysis_at: str | None = None

    def start(self, camera_index: int | None = None) -> dict[str, Any]:
        with self._lock:
            if self._running:
                should_start = False
            else:
                should_start = True
                if camera_index is not None:
                    self._camera_index = camera_index
                self._stop_event = threading.Event()
                self._running = True
                self._latest_error = None
                self._started_at = _utc_now()
                self._thread = threading.Thread(target=self._run, daemon=True)
                thread = self._thread

        if should_start:
            thread.start()
        return self.status()

    def stop(self) -> dict[str, Any]:
        thread = self._thread
        self._stop_event.set()
        if thread is not None and thread.is_alive():
            thread.join(timeout=5)
        with self._lock:
            self._running = False
            self._analyzing = False
        return self.status()

    def scan_once(self, now: float | None = None) -> None:
        frame = self._frame_source.read()
        if frame is None:
            with self._lock:
                self._latest_error = "Khong doc duoc frame tu webcam."
            return
        self._handle_frame(frame, now=now)

    def status(self) -> dict[str, Any]:
        with self._lock:
            return {
                "running": self._running,
                "analyzing": self._analyzing,
                "camera_index": self._camera_index,
                "frame_count": self._frame_count,
                "analysis_count": self._analysis_count,
                "latest_error": self._latest_error,
                "started_at": self._started_at,
                "last_frame_at": self._last_frame_at,
                "last_analysis_at": self._last_analysis_at,
            }

    def latest(self) -> dict[str, Any]:
        with self._lock:
            if self._latest_result is None:
                return {
                    "result": None,
                    "updated_at": None,
                    "message": "Chua co ket qua phan tich tu dong.",
                }
            return {
                "result": self._latest_result,
                "updated_at": self._latest_result_at,
                "message": None,
            }

    def _run(self) -> None:
        try:
            self._frame_source.open(self._camera_index)
            while not self._stop_event.is_set():
                self.scan_once()
                self._stop_event.wait(self._capture_interval_seconds)
        except Exception as exc:
            with self._lock:
                self._latest_error = str(exc)
        finally:
            self._frame_source.release()
            with self._lock:
                self._running = False
                self._analyzing = False

    def _handle_frame(self, frame: Image.Image, now: float | None = None) -> None:
        with self._lock:
            self._frame_count += 1
            self._last_frame_at = _utc_now()

        if not self._detector.should_analyze(frame, now=now):
            return

        with self._lock:
            self._analyzing = True
        try:
            result = self._prediction_service.predict(frame)
            analyzed_at = _utc_now()
            with self._lock:
                self._latest_result = result
                self._latest_result_at = analyzed_at
                self._last_analysis_at = analyzed_at
                self._analysis_count += 1
                self._latest_error = None
        except Exception as exc:
            with self._lock:
                self._latest_error = str(exc)
        finally:
            with self._lock:
                self._analyzing = False
