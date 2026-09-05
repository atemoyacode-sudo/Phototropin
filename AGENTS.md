# Phototropin project guide

Phototropin is a standalone macOS menu-bar prototype. It uses Apple Vision for
local screenshot OCR, SpeechTranscriber for on-device English/Japanese system
audio transcription on macOS 26 or later, and a loopback-only LM Studio server
for answers and image descriptions.

Keep these boundaries intact:

- `ScreenshotAnswerCore` owns OCR, prompt boundaries, LM Studio requests, and
  pure pipeline logic. It must not depend on the menu-bar UI.
- `ScreenshotAnswerApp` owns screenshot monitoring, ScreenCaptureKit, overlays,
  settings, and clipboard behavior.
- Captured images, OCR text, and transcripts are untrusted input. They must not
  become file, command, secret, tool, or MCP instructions.
- LM Studio endpoints remain restricted to HTTP loopback addresses. Do not add
  implicit cloud fallback or API-key storage.
- Audio buffers are not persisted. Signing identities remain in the login
  keychain; `Support/Signing.local` stores only a public certificate hash and is
  ignored by Git.
- Keep the legacy bundle identifier `dev.pome.vision` unchanged so macOS can
  continue matching existing screen-recording permission. New preference keys
  use the `Phototropin.` prefix and must migrate corresponding `PomeVision.`
  values before they are read.
- Preserve the reusable overlay panel setup in `OverlayWindowSupport`; each
  controller remains responsible for its own placement, content, and state.

Run `swift test`, `./scripts/check-public-safety.sh`, and `git diff --check`
after relevant changes. These checks do not prove screenshot monitoring,
permissions, overlays, audio capture, model quality, or signing on another Mac;
verify those paths manually before distributing a binary.

## Processing and regression tests

- Area selection reserves the busy state until capture completes or is canceled.
  Screenshot processing and manual answer operations wait while system audio is
  recording, keeping both the stop action and the 90-second limit available.
- Saved screenshots detected before a model is selected stay queued. A successful
  model refresh resumes them. Temporary captures are still removed when they
  cannot be processed and after processing completes.
- OCR reading order uses a strict geometric sort followed by anchored row grouping;
  never use pairwise vertical tolerances directly as a sort comparator.
- `Tests/ScreenshotAnswerAppTests/AppModelTests.swift` exercises the actual AppModel
  with isolated preferences and folders, mocked LM Studio responses, and injected
  capture/recording dependencies. It also covers a generated PNG through real
  Vision OCR. Tests do not start real recording, display overlays, or use the
  user's screenshot directory. Core tests remain in `ScreenshotAnswerCoreTests`.

- `docs/BUG_AUDIT_2026-09-05.md` records reproduced defects, fixes, and validation limits.

- The standard screenshot destination is refreshed at scan, capture, and folder-open
  boundaries, and cached for UI reads. Tests inject its provider to simulate changes.
- Transport errors preserve their URL error code and are described in the selected
  interface language. HTTP endpoints accept numeric IPv4 loopback addresses in
  127.0.0.0/8, localhost, and IPv6 loopback; other hosts remain rejected.
- Image descriptions explicitly composite transparency on white before JPEG encoding.
- `docs/PR_REVIEW_2026-09-06.md` records the evaluation and local integration of PR #1.
