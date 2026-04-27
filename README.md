# ToiletOnly

ToiletOnly is a multi-part project that combines an iOS app, a FastAPI backend, and an ML training pipeline.

## What is included

- `ToiletOnly` and `ToiletOnly.xcodeproj`: the main SwiftUI iOS application.
- `backend`: REST/WebSocket API for auth, profiles, matching, chat, videos, and safety actions.
- `ml`: dataset tooling, training scripts, model evaluation, and CoreML export workflows.
- `docs`: product strategy and investor demo context.

## Core idea

The app uses on-device CoreML scene detection as an access gate, then provides social discovery features such as profile setup, likes/matches, messaging, video feed, and activity.

## Tech stack

- iOS: SwiftUI, AVFoundation, Vision, CoreML
- Backend: FastAPI, SQLAlchemy, PostgreSQL
- ML: Ultralytics/YOLO-based training and CoreML conversion
