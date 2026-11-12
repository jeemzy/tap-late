# tap-late — Glass Lens

Selected by the user: the Glass Lens concept. Mode: Operate. Preserve the screenshot as content; its colors and typography belong to the uploaded image, not the app theme.

## Viewer

The screenshot dominates, with a compact floating top capsule and a small bottom details island. Controls use a custom WebGL optical layer: curved-edge Snell refraction, 1.045× center magnification, subtle red/blue edge dispersion, neutral surface reflection and a pointer-responsive highlight. Frost is limited to 1 CSS pixel in the interior and 0.18px at the edge. Colors come from locally refracted screenshot pixels; never switch the whole material between dark/light tints. Only foreground text and icons adapt for legibility. Inspected source/translation words have small local contrast backplates.

Capture the content plane only when its content, size or fonts change; reuse the texture while scrolling. Capture and optical backing resolution use at least 2× on desktop and up to 3× on iPhone, bounded by texture dimensions and a 16-megapixel capture budget. The original image and clickable HTML remain the real content; this optical texture is decorative and never an exported translated image. CSS blur is the readable fallback when canvas/WebGL is unavailable. Reduced transparency or increased contrast uses an opaque surface. Selection uses blue `#168cff` with a 2px visible outline.

The viewer stage fills the phone width and stays at a maximum 520px on desktop. Overlays share the screenshot's original coordinate system and a common transform. Source image aspect ratio stays intact. Browser zoom remains enabled.

The island sits 6px from screen sides and above the bottom safe area, with a 32px corner radius and at most 36% viewport height for unusually long text. Normal short selections occupy substantially less. Source and translation remain selectable; long content scrolls inside the island. Closing returns focus to its region without scrolling. Reveal an obscured selection by measuring the actual tapped button and the island's final position, excluding its entrance animation offset.

## Supporting workspace

Apple gray `#f5f5f7` canvas, ink `#1d1d1f`, blue `#007aff` actions and a white upload surface. The sticky workspace header uses the same optical material. Content remains on standard surfaces. The upload task leads; history uses compact image rows rather than repeated cards. On mobile the intro, upload and history stack in order.

Use the Apple/system sans stack for native iPhone familiarity. Control touch areas are normally 44px or larger; OCR region bounds stay faithful and can be magnified with browser zoom. Visible focus uses a 3px blue outline.

## Appearance settings

The home header opens `/settings`. Standard white control groups sit beside a sticky optical test scene on desktop; on phones a compact sticky preview stays above the controls. The same `LiquidGlass` renderer powers the demo and the app. Color, fine-detail and dark scenes demonstrate the material; scene movement is optional and disabled for reduced motion. Each control names its effect and shows its numeric value, including refractive index and magnification. Adaptive, 2× and 3× quality share the capture memory limits.

Changes preview immediately and save automatically after a short debounce. The server owns one configuration for all devices, independent of screenshot expiry. Visible pages synchronize every three seconds and on focus. Pending edits survive a failed save in memory and expose Retry; they are never overwritten by a background refresh. Reset restores global defaults. Accessibility preferences remain device-specific.

## States and motion

Show the original immediately, followed by queued/OCR/translating status and then translations. Failed sessions offer retry; empty recognition explains that no text was found. Missing/expired images have a recovery path to upload. Pending controls disable repeated actions.

The authored motion is the island entering 12px upward over 220ms with exponential ease-out; presses scale to .97 over 160ms. The optical press uses a damped spring and settles to idle without a continuous animation loop. Reduced motion removes positional animation and optical deformation. The top toolbar remains available; controls never depend on hover. WebGL context loss restores readable CSS until the renderer recovers.

## Image boundaries

Translated strings are HTML, never baked into the screenshot. Flat-background cover patches sample around the text. Complex-image patches prioritize readability and may remain visible. Font fitting stops before becoming illegible; overflow is indicated and full text stays in the island.

The source concept is a visual reference, not a screenshot of the finished app or proof of OCR quality. The upload and source screenshots keep their own visual identity.

Material references: [Apple's Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) and [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials). This web renderer is custom; it is not Apple's native system compositor. WebKit's SVG backdrop-displacement support is not assumed.
