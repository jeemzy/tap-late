# tap-late — Glass Lens

Selected by the user: the Glass Lens concept. Mode: Operate. Preserve the screenshot as content; its colors and typography belong to the uploaded image, not the app theme.

## Viewer

The screenshot dominates, with a compact floating top capsule and a small bottom details island. Charcoal glass (`#222725` at 90% opacity) uses an 18px backdrop blur, a restrained glossy rim, and soft offset shadow. Fallback is sufficiently opaque for readable text without blur. Selection uses blue `#168cff` with a 2px visible outline. Controls and details use near-white text with readable sage-tinted secondary text.

The viewer stage fills the phone width and stays at a maximum 520px on desktop. Overlays share the screenshot's original coordinate system and a common transform. Source image aspect ratio stays intact. Browser zoom remains enabled.

The island sits 6px from screen sides and above the bottom safe area, with a 30px corner radius and at most 36% viewport height for unusually long text. Normal short selections occupy substantially less. Source and translation remain selectable; long content scrolls inside the island. Closing returns focus to its region.

## Supporting workspace

Warm neutral `#f6f7f3` canvas, ink `#17211c`, muted green `#273e32` actions, and pale green upload surface `#eef1e9`. The upload task leads; history uses compact image rows rather than repeated cards. On mobile the intro, upload and history stack in order.

Use the Apple/system sans stack for native iPhone familiarity. Control touch areas are normally 44px or larger; OCR region bounds stay faithful and can be magnified with browser zoom. Visible focus uses a 3px blue outline.

## States and motion

Show the original immediately, followed by queued/OCR/translating status and then translations. Failed sessions offer retry; empty recognition explains that no text was found. Missing/expired images have a recovery path to upload. Pending controls disable repeated actions.

The authored motion is the island entering 12px upward over 220ms with exponential ease-out; presses scale to .97 over 160ms. Reduced motion removes positional animation. The top toolbar remains available; controls never depend on hover.

## Image boundaries

Translated strings are HTML, never baked into the screenshot. Flat-background cover patches sample around the text. Complex-image patches prioritize readability and may remain visible. Font fitting stops before becoming illegible; overflow is indicated and full text stays in the island.

The source concept is a visual reference, not a screenshot of the finished app or proof of OCR quality. The upload and source screenshots keep their own visual identity.
