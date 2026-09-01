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
