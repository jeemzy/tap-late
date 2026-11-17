# Native iPhone app

The native app is separate from the PC-hosted website. Stage 1 provides a screenshot AppIntent, single-image Photos import, Vision OCR, Apple Fast Chinese-to-English translation, native Liquid Glass controls, and a persistent processing queue. It does not need the PC after installation.

## Install or update from Windows

1. Open the **iOS** workflow run for the native branch in GitHub Actions. Download the **tap-late-unsigned** artifact and extract its ZIP to get `tap-late-unsigned.ipa`.
2. Connect and unlock the iPhone. Import that IPA into your existing Windows iloader and use the account/team you normally sign apps with. iloader handles signing and provisioning locally; do not put Apple credentials or signing keys in this repository or GitHub Actions.
3. Complete the normal device trust/Developer Mode prompts if iOS requests them, then launch **tap-late**.
4. Open **Settings → Prepare offline translation** in tap-late and allow Apple's Chinese/English language download. Once prepared, Apple Fast translates on-device without an internet connection.

For an update, use the same effective bundle identifier and signing identity/team and install over the existing app. The build's bundle identifier is `com.jeemzy.taplate`; record the effective identifier if iloader changes it. Changing identity or uninstalling can affect access to stored data. Settings includes a harmless secure-storage check for validating the installation/update path; it is not an API credential.

GitHub builds an unsigned **device** app, not a simulator app. iloader supplies the device signature. A successful build does not prove installation, AppIntent indexing, or offline translation on your phone; those checks require the physical iPhone.

## Set up Back Tap

Create a Shortcut named **tap-late**:

1. If **Shortcut Input** contains an image, use that image. Otherwise run **Take Screenshot**.
2. Add **tap-late → Translate Screenshot** and put that image in its **Screenshot** parameter. Leave the optional engine override unset to use the app default, or explicitly choose Apple Fast for this capture.
3. In iPhone **Settings → Accessibility → Touch → Back Tap**, assign the Shortcut to double or triple tap.

Capture must happen **before** the tap-late action opens the app. The app action does not silently capture the previously foregrounded app. It copies the incoming image into private storage, opens its original, and returns without waiting for translation. There is no upload-to-PC or Safari step, and no Shortcuts Use Model translation step.

For a simpler Back Tap-only Shortcut, use **Take Screenshot → Translate Screenshot**. The supplied-input branch is useful for other Shortcut callers. This guide describes manual setup; the repository does not promise an automatically signed `.shortcut` download.

## Read and recover a translation

- The original opens immediately. Queued, reading, translating, download-needed, empty, and failed states explain progress.
- Pinch and pan natively. Use the layers control for original/translated view. Tap a text region for selectable original/full translation and copy controls in the details island. Zoom small text areas before tapping if necessary.
- Every capture is saved; work runs in capture order. The newest original opens immediately while earlier captures finish. The home screen's Queue opens unfinished captures; **Open last screenshot** returns to the latest one.
- First results can appear progressively. **Retry unfinished regions** keeps completed work and recognized geometry. **Translate again** starts a replacement, keeping the previous complete result visible until the replacement succeeds.
- Leaving the app does not guarantee background completion. Work is checkpointed and resumed when you return. An unavailable engine never automatically switches to another provider.

Stage 1 exposes Apple Fast only. High Fidelity, the experimental on-device Foundation Model, direct personal-key OpenAI, grouped history/24-hour expiry, and currency conversion are subsequent stages. In this early build, captures remain in private local storage; grouped retention is not yet active. Native data is independent of website history and excluded from backups.

## Build and verification

The maintained project specification is in the native directory. CI pins XcodeGen 2.47.0 and verifies its archive digest, selects Xcode 27.1 on the `xcode-27` runner, runs the Swift package's public Session tests, builds the unsigned IPA, and runs native simulator tests. Simulator captures and results are uploaded as **simulator-verification**.

With an appropriate Mac/Xcode installation, the equivalent core command is `swift test --package-path ios`; generate the Xcode project with the pinned generator before building the TapLate scheme. The Windows workflow uses GitHub's Mac runner instead.

UI automation uses an explicitly labeled deterministic screenshot fixture in Debug only. The Release IPA contains no fake engine or fixture activation path. Simulator UI fixtures test layout and interaction, not Apple translation accuracy. Real-device checks cover cold/warm Shortcut handoff, secure storage across updates, offline model readiness, translation correctness and timing, and interruption recovery.
