# Webcam Auto Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add continuous laptop/webcam scanning through the Python backend and let Flutter show/start/stop the automatic monitor.

**Architecture:** The backend owns the physical webcam through an `AutoWebcamMonitor` service, running in a background thread and storing status/latest prediction in memory. FastAPI exposes monitor endpoints, while Flutter derives the backend base URL from the existing `/predict` URL and polls monitor state.

**Tech Stack:** Python FastAPI, Pillow, OpenCV for webcam capture, unittest/TestClient, Flutter Web, Dart HTTP.

---

### File Structure

- Create `backend/camera_monitor.py`: monitor status dataclass, frame source protocol, OpenCV webcam adapter, change detector, background monitor.
- Modify `backend/app.py`: inject monitor dependency and expose `/monitor/start`, `/monitor/stop`, `/monitor/status`, `/monitor/latest`.
- Modify `backend/requirements.txt`: add `opencv-python-headless`.
- Create `backend/tests/test_camera_monitor.py`: unit tests using fake frame source and fake prediction service.
- Modify `backend/tests/test_app.py`: API tests using a fake monitor.
- Modify `lib/ai_backend_config.dart`: add `resolveAiBackendBaseUrl`.
- Modify `test/ai_backend_config_test.dart`: test monitor base URL derivation.
- Modify `lib/main.dart`: poll monitor endpoints and replace one-shot analysis button with automatic scan controls.

### Task 1: Backend Base URL Helper

**Files:**
- Modify: `test/ai_backend_config_test.dart`
- Modify: `lib/ai_backend_config.dart`

- [ ] **Step 1: Write the failing test**

Add tests asserting `resolveAiBackendBaseUrl('http://localhost:8000/predict') == 'http://localhost:8000'` and preserves explicit nonstandard paths by trimming the last segment.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ai_backend_config_test.dart`
Expected: FAIL because `resolveAiBackendBaseUrl` is not defined.

- [ ] **Step 3: Write minimal implementation**

Add a pure Dart helper that trims the URL and strips the `/predict` suffix when present.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ai_backend_config_test.dart`
Expected: PASS.

### Task 2: Backend Monitor Core

**Files:**
- Create: `backend/camera_monitor.py`
- Create: `backend/tests/test_camera_monitor.py`

- [ ] **Step 1: Write failing tests**

Add tests for: first frame triggers analysis, unchanged frame before the interval is skipped, changed frame triggers analysis, and monitor status/latest result update after processing a fake frame.

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest backend/tests/test_camera_monitor.py -q`
Expected: FAIL because `backend.camera_monitor` does not exist.

- [ ] **Step 3: Write minimal implementation**

Implement `FrameChangeDetector`, `FrameSource`, `OpenCvWebcamSource`, `AutoWebcamMonitor.start`, `stop`, `status`, `latest`, and `scan_once`.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest backend/tests/test_camera_monitor.py -q`
Expected: PASS.

### Task 3: Monitor API

**Files:**
- Modify: `backend/app.py`
- Modify: `backend/tests/test_app.py`
- Modify: `backend/requirements.txt`

- [ ] **Step 1: Write failing API tests**

Add tests for `/monitor/start`, `/monitor/stop`, `/monitor/status`, and `/monitor/latest` using a fake monitor object.

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest backend/tests/test_app.py -q`
Expected: FAIL because monitor routes do not exist.

- [ ] **Step 3: Write minimal implementation**

Add a `monitor_factory` dependency to `create_app`, build the default monitor from `build_service`, and expose the four endpoints.

- [ ] **Step 4: Run backend tests**

Run: `python -m pytest backend/tests -q`
Expected: PASS.

### Task 4: Flutter Camera Page Integration

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add monitor state and polling**

Add `Timer? _monitorPollTimer`, status/latest state maps, and HTTP helpers for `/monitor/status` and `/monitor/latest`.

- [ ] **Step 2: Add start/stop actions**

Add `_startAutoMonitor` and `_stopAutoMonitor` methods that POST to backend endpoints and refresh state.

- [ ] **Step 3: Update UI controls**

Replace the one-shot "Phan tich AI" button with an automatic scan toggle and show scanner status in the overlay.

- [ ] **Step 4: Verify Flutter analysis**

Run: `flutter analyze`
Expected: no new analyzer errors from the edited files.

### Task 5: Final Verification

**Files:**
- Review all modified files.

- [ ] **Step 1: Run focused backend tests**

Run: `python -m pytest backend/tests -q`
Expected: PASS.

- [ ] **Step 2: Run focused Flutter tests/analyzer**

Run: `flutter test test/ai_backend_config_test.dart` and `flutter analyze`
Expected: PASS, or report existing unrelated failures exactly.

- [ ] **Step 3: Review git diff**

Run: `git diff --stat` and `git diff --check`
Expected: no whitespace errors and only planned files changed.
