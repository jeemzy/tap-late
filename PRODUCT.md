# tap-late

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

- Self-hosted Docker application running on the user's PC.
- FastAPI backend for uploads, processing, session storage, and API access.
- React + Vite, TypeScript, Tailwind CSS and shadcn/ui; FastAPI serves the compiled frontend from one Docker container.
- An iOS Shortcut initiates capture and opens the web viewer; a native iOS application is not required.

## Users

iPhone users browsing Chinese shopping apps such as Weidian, 1688, Taobao, Alibaba, JD, Pinduoduo and Dewu. The initial use case is the owner's iPhone connecting to their PC-hosted service over trusted Wi-Fi and an existing WireGuard private network.

## Product Purpose

Translate text in iPhone screenshots while preserving its original location and keeping each translation interactive. Success means opening a translated screenshot, understanding it in context, and tapping any translated region to inspect both the original and translated text.

## Positioning

OCR defines independent translation slots and their geometry; a vision-capable LLM translates those slots using the whole screenshot for context. The model chooses wording, never placement. Repeated words in different regions retain separate identities.

## Operating Context

1. Back Tap or the Action Button triggers an iOS Shortcut.
2. The Shortcut captures a screenshot, generates a UUID, uploads the screenshot to the PC's FastAPI service, and opens `/view/<uuid>`.
3. The PC processes the screenshot and makes its interactive translation available at that session URL.
4. The user views the screenshot on their iPhone and taps translated text for details.

The intended sequence is Back Tap → Screenshot → Upload → OCR → Context-aware LLM translation → Interactive translated webpage.

## Capabilities and Constraints

- OCR detects text, extracts content and bounding boxes, and assigns stable region IDs such as `r001` and `r002` within each screenshot.
- Generate an annotated copy with visible region boxes and IDs.
- Supply the vision LLM with the original screenshot, annotated screenshot, and OCR region data.
- Receive structured JSON mapping region IDs to translated strings. Preserve independent entries even when source strings match.
- Display the original screenshot with its correct aspect ratio and interactive HTML translation overlays. Do not flatten the result into a permanently translated image.
- Anchor overlays to OCR geometry across display scaling. Fit translated text using appropriate size, wrapping, and background treatment.
- Make every translated region clickable and show its source and translation in a compact floating panel at the bottom.
- Offer server-wide Liquid Glass appearance settings with a live optical demo. Changes apply across devices, persist after restarts, and preserve each device's accessibility preferences.
- Prioritize accurate positioning, contextual translation, a polished mobile-first interaction, and a simple practical implementation.
- The Shortcut must be able to upload using its own UUID and open the corresponding viewer; API details remain to be designed.
- Chinese → English, including mixed Latin brand names, numbers and SKU text.
- RapidOCR PP-OCRv6 medium through ONNX Runtime CUDA on the PC's NVIDIA GPU, with explicit CPU configuration available; OpenAI Responses API with configurable gpt-6.1-sol. All three OCR models validate their execution provider and reject silent CPU fallback.
- The model may correct OCR source transcription within fixed regions; raw OCR is retained separately.
- Fixed overlay positions, bounded text fitting and practical cover patches; full translations appear in the island.
- Private Wi-Fi/WireGuard access without app login; server-side API credentials.
- Manual uploads, recent-session history and deletion; persistent sessions expire seven days after creation.
- Ordinary PNG/JPEG/WebP screen captures; long captures, PDF and inpainting are outside v1.

## Brand Commitments

- Product name: tap-late.
- The details panel should feel like a native iOS system overlay or bottom Dynamic Island: rounded corners, clear optical glass with a trace of frost, curved-edge refraction, slight chromatic dispersion, smooth animation, and very small side/bottom margins, approximately 1–2 mm in the user's description. Color follows local lensing rather than an abrupt material tint switch.
- Keep the panel compact so that it does not cover too much of the screenshot.
- Glass Lens is the selected visual direction; DESIGN.md records its implementation rules.

## Evidence on Hand

- A confirmed product brief and pipeline examples supplied by the user.
- Example independent source regions: `r001: What?`, `r002: Box`, `r003: What?`.
- Example translations: `r001: Чего?`, `r002: Коробка`, `r003: Чего?`.
- No user-provided screenshots, logo, or other visual assets are present yet. Any concept screenshot is illustrative sample content, not evidence of OCR or translation performance.

## Product Principles

1. Geometry belongs to OCR; contextual wording belongs to the translation model.
2. Preserve the screenshot's spatial meaning as it scales.
3. Keep source text one tap away from each translated region.
4. Let the screenshot occupy the experience; supporting controls and details stay compact.
5. Prefer a simple self-hosted system with explicit configuration over unnecessary infrastructure.
