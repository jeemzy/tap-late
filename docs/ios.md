# Native iPhone app

The native app is separate from the PC-hosted website. Stage 1 provides a screenshot AppIntent, single-image Photos import, Vision OCR, Apple Fast Chinese-to-English translation, native Liquid Glass controls, and a persistent processing queue. It does not need the PC after installation.

## Install or update from Windows

1. In GitHub Actions, run **iOS** on the native branch with **build_device** enabled. Download **tap-late-unsigned** from that run and extract its ZIP to get `tap-late-unsigned.ipa`.
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
- The overlay fits each translation inside its source line and uses colors sampled from the screenshot. When Apple can carry a color change through translation, distinct phrases keep their colors. Long lines can show an ellipsis. Tap them to read the full translation.
- Every capture is saved; work runs in capture order. The newest original opens immediately while earlier captures finish. The home screen's Queue opens unfinished captures; **Open last screenshot** returns to the latest one.
- First results can appear progressively. **Retry unfinished regions** keeps completed work and recognized geometry. **Translate again** starts a replacement, keeping the previous complete result visible until the replacement succeeds.
- Leaving the app does not guarantee background completion. Work is checkpointed and resumed when you return. An unavailable engine never automatically switches to another provider.

Stage 1 exposes Apple Fast only. High Fidelity, the experimental on-device Foundation Model, direct personal-key OpenAI, grouped history/24-hour expiry, and currency conversion are subsequent stages. In this early build, captures remain in private local storage; grouped retention is not yet active. Native data is independent of website history and excluded from backups.

## Build and verification

Pushes to the native branch and relevant pull requests run the Swift package's Session tests on Ubuntu. To use a macOS runner, dispatch **iOS** and enable the job you need. **build_device** packages an IPA for iloader. **run_simulator_tests** runs native integration and UI tests on **iPhone 17 Pro Max, iOS 27.2** and uploads **simulator-verification**. The Mac jobs pin Xcode 27.2 and verify the XcodeGen 2.47.0 archive digest.

Run the core suite on Linux or macOS with `swift test --package-path ios`. For a local Xcode build, generate the Xcode project with the pinned generator before building the TapLate scheme.

UI automation uses an explicitly labeled deterministic screenshot fixture in Debug only. The Release IPA contains no fake engine or fixture activation path. Simulator UI fixtures test layout and interaction, not Apple translation accuracy. Real-device checks cover cold/warm Shortcut handoff, secure storage across updates, offline model readiness, translation correctness and timing, and interruption recovery.

## Run checks on an iPhone from Windows

Install the device IPA with iloader. Connect and unlock the iPhone, accept the normal trust prompt if it appears, and select the phone under **Local Devices** in [MobAI](https://mobai.run/devices). Use **Start Bridge** and follow MobAI's local Apple signing flow if prompted. Once the bridge is running, MobAI can launch tap-late and drive the viewer, Photos import, and onscreen Shortcuts checks without a GitHub runner. Trigger the physical Back Tap gesture by hand. Use a synthetic or non-sensitive screenshot for repeatable checks.

## Live simulator from Windows

The optional **iOS live preview** workflow builds a separate unsigned simulator `.app.zip` and verifies the pinned MobAI CLI's sharing command. Regular pushes do not open a remote session. The device IPA and existing XCTest regressions remain in the **iOS** workflow.

To enable interactive use, install [MobAI for Windows](https://mobai.run/download), sign in, create an API key under **Account → API Keys**, and save it as the repository Actions secret **MOBAI_API_KEY**. Use GitHub's secret form or `gh secret set MOBAI_API_KEY`; never put the key in source or chat. Run **iOS live preview** against the desired native branch with **share_simulator** enabled. The **iPhone 17 Pro Max / iOS 27.2** simulator appears in MobAI's **CI Devices** as **tap-late native preview**; choose **Open the device**. Keep its bridge running while testing. **Stop Bridge** releases the hosted device and requires a fresh workflow session to reconnect. Release it when finished; the session expires after 10 minutes of inactivity and the job has a 35-minute hard limit.

The preview opens the full-resolution synthetic fixture for zoom, selection and navigation checks. It is a Debug build with a deterministic preview engine, not evidence of translation accuracy or physical-device timing. Use the Release IPA on the iPhone for those checks. Simulator availability does not require a local macOS VM or Apple signing keys.

[MobAI's Builder documentation](https://github.com/MobAI-App/ios-builder#quick-start) describes simulator sharing as free with an account on MobAI 3.0+. Its [agent interface](https://github.com/MobAI-App/mobai-mcp) requires the desktop app running locally. No paid plan, global agent configuration, or automatic app registration is created by this repository workflow.
