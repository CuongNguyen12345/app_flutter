# Webcam Auto Monitor Design

## Goal

Use the laptop/webcam camera as a continuously running scanner. The user should not need to press "Phan tich AI" for each frame. The camera should keep scanning while the Flutter UI is closed as long as the Python backend process is still running on the laptop.

## Constraints

- Browser-based Flutter cannot keep using `getUserMedia` after the tab or app is closed.
- A backend process can keep the webcam open independently of the Flutter UI.
- The webcam can be used by only one process at a time. If another app owns the camera, the backend must report an error.
- Continuous AI inference can be expensive, so scanning should use a configurable interval and skip frames that have not changed enough.

## Recommended Architecture

Move continuous webcam ownership to the FastAPI backend. Add a background monitor service that opens the webcam with OpenCV, captures frames, runs lightweight motion/change detection, and calls the existing `PredictionService` only when analysis is due. The Flutter app becomes a monitor dashboard that starts/stops scanning and polls backend status/latest result.

## Backend Behavior

- `POST /monitor/start` starts a background monitor thread if it is not already running.
- `POST /monitor/stop` stops the monitor thread and releases the webcam.
- `GET /monitor/status` returns running state, camera index, frame count, analysis count, latest error, and timestamps.
- `GET /monitor/latest` returns the latest prediction result or a clear "no result yet" response.
- The monitor captures one frame at a time, compares it to the previous frame, and runs AI when either enough visual change is detected or the regular interval has elapsed.
- The service stores the latest successful prediction in memory for the UI to read.

## Flutter Behavior

- Replace the manual one-shot "Phan tich AI" action with automatic scan controls.
- Show backend scanner status: running, stopped, analyzing, error.
- Poll `/monitor/status` and `/monitor/latest` every few seconds while the Camera page is open.
- Keep the existing in-browser webcam preview as optional UI, but make AI results come from backend monitoring.
- Surface useful errors when the backend is offline or the webcam is busy.

## Testing

- Unit test the monitor service with fake camera frames and fake prediction service.
- API test start/stop/status/latest endpoints with a fake monitor to avoid requiring physical camera hardware.
- Existing prediction tests should keep passing.
- Flutter tests should cover pure config helpers where practical. Browser camera behavior remains manual/integration-level.

## Out Of Scope

- Running camera after the laptop is shut down.
- Android foreground camera service.
- Multi-camera selection UI beyond a default camera index.
