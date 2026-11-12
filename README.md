# tap-late

Chinese screenshots. English, right where it belongs.

A personal screenshot translator for Chinese shopping apps such as Taobao, 1688, Weidian, JD, Pinduoduo and Dewu. Local OCR defines text regions; OpenAI translates them using both the original and an annotated screenshot. The viewer keeps translations as clickable HTML over the original image.

## Run with Docker

1. Copy `.env.example` to `.env` and set `OPENAI_API_KEY`. The default model is `gpt-6.1-sol`; change `OPENAI_MODEL` if needed.
2. Start Docker Desktop with Linux containers.
3. Run:

   ```sh
   docker compose up --build -d
   ```

4. Open `http://localhost:8000`. On your iPhone, use the PC's private LAN/WireGuard IP instead of `localhost`.

The initial build downloads the pinned OCR models and can take several minutes. Screenshots and SQLite live in the `tap-late-data` Docker volume. Updating or restarting the container preserves them. `docker compose down` preserves data; adding `--volumes` removes it.

This is a trusted-private-network app without a login. Anyone who can reach its port can view recent sessions, upload, or delete them. Keep access within your LAN/WireGuard network. `TAPLATE_BIND_ADDRESS` can restrict the host binding to a specific private interface.

The screenshots and OCR text are sent to OpenAI for translation. The API key stays on the backend; Responses API result storage is disabled. No API key is needed in the Shortcut or browser. Runtime images, `.env`, and local model files are excluded from Git and the Docker build context.

## Use it

- Upload an ordinary single-screen PNG, JPEG, or WebP (up to 20 MB / 25 megapixels).
- Open the viewer immediately while OCR and translation run.
- Tap any region to inspect its source and full English translation. The layers control switches original/translated views. Browser pinch zoom remains available.
- The source shown is the model-corrected transcription; raw OCR remains available in the session API.
- English stays within the original bounds. Dense text may be shortened visually; the island contains the full returned translation. Complex photo backgrounds use visible cover patches rather than image reconstruction.
- Recent sessions expire seven days after upload. Delete sooner from the home page, or retry a failed session in its viewer. Interrupted jobs become retryable after restart.

[Set up the iPhone Shortcut](docs/shortcut.md).

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENAI_API_KEY` | empty | OpenAI API key, server-side only |
| `OPENAI_MODEL` | `gpt-6.1-sol` | Vision model supporting structured outputs |
| `TAPLATE_PORT` | `8000` | Docker host port |
| `TAPLATE_BIND_ADDRESS` | `0.0.0.0` | Docker host interface |
| `TAPLATE_RETENTION_DAYS` | `7` | Session lifetime |
| `TAPLATE_DATA_DIR` | `./data` locally, `/data` in Docker | SQLite and images |
| `TAPLATE_MODEL_DIR` | `./.models` locally | Provisioned OCR model directory |
| `TAPLATE_OCR_MODEL` | `medium` | Local development model size (`small` or `medium`) |

The Docker image provisions `medium`. To change model size for a custom image, set the same model size during provisioning and runtime, then rebuild. Changing a key/model in `.env` requires recreating the container: `docker compose up -d --force-recreate`.

## Local development

Requires Python 3.12, [uv](https://docs.astral.sh/uv/), and Node 22.12+.

```sh
uv sync --locked
uv run python -m taplate.download_models
cd frontend
npm ci
npm run build
cd ..
uv run uvicorn taplate.app:create_app --factory --host 127.0.0.1 --port 8000
```

For frontend iteration, run `npm run dev` in `frontend` alongside the API; Vite proxies `/api` to port 8000. Production uses FastAPI to serve built assets, not the Vite development server. Run only one backend worker: processing and restart recovery assume a single process.

```sh
uv run pytest
uv run ruff check taplate tests
cd frontend
npm run build
```

Tests exercise the HTTP API with real temporary persistence and deterministic external-service adapters. The synthetic shopping screenshot in `tests/fixtures` contains no personal data. It checks mixed scripts and layout; it does not establish accuracy on actual shopping screenshots.

## API

`POST /api/sessions` takes multipart `file` and optional UUID `session_id`; returns `{ "id": "…", "view_url": "/view/…" }` immediately. Same UUID and normalized image is idempotent; a different image under the same UUID returns 409.

`GET /api/sessions` lists recent sessions. `GET /api/sessions/{id}` returns processing state, geometry, source text, translations and image URLs. `POST /api/sessions/{id}/retry` retries failures; `DELETE /api/sessions/{id}` removes the session and files. `/docs` exposes the interactive API reference.

No scraping, purchasing, currency conversion, PDF/long-capture processing, flattened translation exports, or inpainting is included.
