# AI Model Files

Put your trained model files in this folder before running the AI backend.

Expected files:

- `best.pt` - YOLOv8 model for detecting leaf bounding boxes.
- `efficientnetb3.pth` - EfficientNetB3 checkpoint for disease classification.

These weight files are ignored by Git because they can be large. Keep the exact
filenames above unless you also update the backend configuration.
