# Volio

Volio is a local-first MVP for organizing a child's artwork portfolio.

The Mac experience is now **Volio Desktop**, an Electron app that starts the local
FastAPI service automatically. The native iOS app is **Volio**. In the first native
prototype, iPhone connects to Volio Desktop over the same Wi-Fi network and uses the
Mac as the private archive and local AI engine.

V0 workflow:

1. AirDrop artwork photos to your Mac.
2. Open Volio in the browser.
3. Import a batch of images.
4. Let the local Ollama vision model draft titles, descriptions, and tags.
5. Review and edit each artwork.
6. Export PDF, ZIP, or JSON.

## Run Volio Desktop

Double-click the app icon:

```text
Volio.app
```

There is also a desktop alias named `Volio`.

Manual Electron run:

```bash
npm install
npm run electron
```

Electron will pick a free local port starting at `8001`, launch the backend on your
Mac, and open the Volio desktop window.

## Run Native iOS App

Open the Xcode project:

```text
ios/Volio/Volio.xcodeproj
```

Build and run the `Volio` scheme on an iPhone or iOS Simulator. For real device use,
set your Apple Developer Team and bundle identifier in Xcode.

Pairing flow:

1. Open Volio Desktop on the Mac.
2. Choose **Connect iPhone** in the sidebar.
3. Open Volio on iPhone and scan the QR code.
4. Keep both devices on the same Wi-Fi network.

The iOS app stores only the recent pairing details locally. The Mac remains the source
of truth for SQLite data, media files, exports, and Ollama analysis.

## Run As Web App

The old browser-based launcher is still available as a fallback:

```bash
./scripts/start_volio.command
```

To stop the background server:

```text
scripts/stop_volio.command
```

Manual run:

```bash
python3 -m uvicorn server.main:app --reload --host 127.0.0.1 --port 8001
```

Then open:

```text
http://127.0.0.1:8001
```

## iPhone Import

Use **Phone Import** inside Volio. The desktop app creates a one-hour upload session
and shows a QR code. Scan it with iPhone, take or choose photos, and Volio imports
them into the local library over the same Wi-Fi network.

## Local AI

The default model is:

```text
minicpm-v4.5:8b
```

Change it with:

```bash
export VOLIO_OLLAMA_MODEL="another-vision-model"
```

Volio expects Ollama at:

```text
http://127.0.0.1:11434
```

Change it with:

```bash
export VOLIO_OLLAMA_URL="http://127.0.0.1:11434"
```

## AI Background Processing

AI analysis runs in a background thread. Controls:

- **Idle timeout**: AI processes only after 5 minutes of inactivity.
  ```bash
  export VOLIO_AI_IDLE_TIMEOUT=300  # seconds
  ```

- **Time window**: Only process during certain hours.
  ```bash
  export VOLIO_AI_WINDOW="23:00-08:00"  # overnight only
  ```

- **Concurrency**: Process N images in parallel (default 1).
  ```bash
  export VOLIO_AI_CONCURRENCY=2
  ```

Queue controls are available in the sidebar and via the API.

## Data

Volio stores data locally:

```text
data/volio.sqlite
library/originals/
library/thumbnails/
exports/
```

Original images are copied into Volio's library. Source files from AirDrop are not modified.

## Data model direction

V0 still speaks in child/artwork language because the first use case is organizing children's drawings.

The database already leaves room for the longer path:

```text
children       -> future people / creators
artworks       -> creative works
projects       -> project timeline, process, final works
work_files     -> original, thumbnail, draft, process shot, final, video, document
tags           -> themes, colors, materials, techniques, custom labels
```

This keeps the product narrow on the surface while allowing Volio to grow into a long-term creative archive.
