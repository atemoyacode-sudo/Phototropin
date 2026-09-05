# Phototropin

Phototropin is a standalone macOS menu-bar prototype that answers questions found in screenshots. It performs Japanese and English OCR locally with Apple Vision, sends the recognized content only to a loopback LM Studio server, and displays the answer in the lower-left corner of the screen. On macOS 26 or later, it can also transcribe currently playing system audio on-device so you can answer listening exercises or ask questions about videos.

Normal use does not require Terminal. After launching the app once, take a screenshot as usual with `Command-Shift-4` and wait for the answer card.

## Features

- Watches the standard macOS screenshot destination once per second.
- Detects newly saved screenshots with common Japanese and English filenames.
- Recognizes Japanese and English text with Vision `VNRecognizeTextRequest`.
- Lists answer-capable models exposed by the LM Studio Local Server.
- Optionally sends a compatible Draft Model only when explicitly selected under advanced generation settings.
- Shows answers for 20 seconds in the lower-left corner across all Spaces.
- Lets you copy or dismiss an answer directly from the overlay.
- Provides model selection and screenshot-monitoring controls from the menu bar.
- Asks for Japanese or English UI language only on first launch, then keeps the choice available from the unobtrusive settings button.
- Lets region captures use the standard macOS screenshot destination, a custom folder, or temporary storage that is deleted after processing and recovered after an interrupted run.
- Monitors a selected custom folder alongside the standard macOS screenshot destination, including screenshots saved there by other apps.
- Uses a pomegranate-shaped template menu-bar icon that adapts to macOS appearances, plus a full-color app icon.
- Captures a selected region from the menu-bar button or with `Control-Option-Command-4`.
- Hides the settings panel and existing answer overlay before region selection so covered areas remain selectable.
- Automatically explains captured content with the closest available vision model when OCR does not contain an answerable question.
- Uses collapsible sections for recognized text and answers.
- Automatically describes photos, scenery, and other images containing no readable text by sending a resized image to a vision-capable local model.
- Captures up to 90 seconds of system audio with ScreenCaptureKit on macOS 26 or later.
- Transcribes English or Japanese audio on-device with SpeechTranscriber.
- Keeps a stop control visible in the upper-right corner across all Spaces while recording; optional details show elapsed time, the question, and live transcription.
- Preserves finalized speech segments on separate lines and can ask the selected LM Studio model to organize likely multi-speaker content as an inferred dialogue.
- Answers free-form questions about captured audio alone or combines it with the most recent screenshot OCR for listening exercises.
- Never saves captured audio files; transcription buffers are discarded after stopping.
- Treats instructions found in images, OCR, and transcripts as untrusted input.
- Includes a CLI for isolating OCR and model-response problems during development.

For the example sentence “She can't get ___ the shock yet,” the expected choice is `4 over`: “get over the shock” means to recover from or overcome the shock.

## Requirements

- macOS 14 or later; system-audio transcription requires macOS 26 or later.
- An Xcode 26-series Swift toolchain with Swift 6.2 or later.
- A valid `Apple Development` signing certificate in the login keychain. A free Personal Team certificate is sufficient for local use.
- [LM Studio](https://lmstudio.ai/) and a downloaded local language model. Describing images without text requires a vision-capable model.

Download a model in LM Studio and start the Local Server from the Developer screen. If you use the LM Studio CLI, the equivalent commands are:

```sh
lms server start
lms ps
```

LM Studio uses port 1234 by default. Phototropin obtains selectable LLMs from the native `GET /api/v1/models` endpoint and generates responses through the OpenAI-compatible `POST /v1/chat/completions` endpoint. Connections are restricted to plain HTTP loopback addresses: `127.0.0.1`, `localhost`, and `::1`. Images and OCR text are not sent to cloud APIs, and the app does not request tools or MCP access. LM Studio configurations that require API authentication are not currently supported. Response quality depends on the selected local model.

Expanding the advanced generation settings lets you select a separate, compatible small model as a conventional Draft Model. Phototropin adds `draft_model` to the request only when this option is selected; the default leaves LM Studio's loading configuration untouched. MTP and DSpark are model-loading runtime features rather than per-response options. Phototropin uses them when they are already enabled in LM Studio and does not modify private LM Studio settings or reload models automatically.

## Using Phototropin

1. Launch LM Studio, load an answer-capable model, and start the Local Server at the default `http://localhost:1234` address.
2. Open `dist/Phototropin.app` and choose Japanese or English for the interface on first launch.
3. Open the pomegranate icon in the menu bar and select an LM Studio model once. The interface language, monitored custom folder, and region-capture storage can later be changed from the settings button at the bottom of the panel.
4. Take a screenshot of a question with `Command-Shift-4` or another standard macOS capture command.
5. After OCR and generation finish, the answer card appears in the lower-left corner.

The card disappears automatically after 20 seconds. You can also copy the answer or close the card immediately.

If OCR does not contain a question, Phototropin automatically selects the vision-capable model whose declared parameter count is closest to the current model and asks it to explain the page type, important content, and any uncertainty. The same path handles a photo or landscape with no recognized text by sending a resized copy of the image directly to the local vision model. If no vision model is available, the app explains why answering was stopped. English questions receive English answers; other content receives Japanese answers, with uncertain context identified before the answer.

### Asking about currently playing audio

1. In the menu-bar panel, choose English or Japanese under the current-audio section.
2. Optionally enter a question such as “What is the speaker claiming?” If the field is empty and screenshot OCR is available, Phototropin uses the audio as evidence for the on-screen question.
3. Optionally enable inferred multi-speaker dialogue organization, then start listening. The main panel closes and a small recording controller appears in the upper-right corner across all Spaces.
4. After playing the relevant audio, select “Stop and answer” in the recording controller. You do not need to reopen the menu bar. The details disclosure shows the current question and live transcript, and recording stops automatically after 90 seconds.
5. Phototropin displays the transcript and answer. You can edit the question and ask again using the same transcript.

The first recording requires permission for screen and system-audio recording and for speech recognition. If the selected language asset is not installed, macOS may download it during first use.

SpeechTranscriber does not provide voiceprint-based speaker identification. Speaker labels such as `Speaker A` and `Speaker B` are inferred by the selected LM Studio model from utterance boundaries, forms of address, questions, and replies. Phototropin prefers the smallest number of speakers that makes the conversation coherent and identifies the result as an inference. This is not strict speaker diarization.

## Building from source

### One-time Xcode signing setup

The repository publishes source code only and does not distribute binaries signed by the author's identity. Each user creates a local development certificate once:

1. Open Xcode and choose `Xcode > Settings... > Accounts`.
2. Use `+` to sign in with your Apple Account. Free accounts appear as a Personal Team.
3. Select the account or team and open `Manage Certificates...`.
4. Use `+` to create one `Apple Development` certificate, then close the dialog.

The private key remains only in that Mac's login keychain and is never sent to GitHub or Phototropin. Local use does not require opening an Xcode project, registering a Bundle ID, obtaining a Developer ID certificate, or notarizing the app.

After cloning the repository, build and open a signed app with:

```sh
git clone https://github.com/atemoyacode-sudo/Phototropin.git
cd Phototropin
./scripts/build-app.sh
open "dist/Phototropin.app"
```

If exactly one valid Apple Development identity exists, the script selects it automatically. If several identities exist, provide the certificate fingerprint as described below.

### Development commands

Run the tests or the SwiftPM executable directly with:

```sh
swift test
swift run Phototropin
```

Build the signed app bundle with:

```sh
./scripts/build-app.sh
open "dist/Phototropin.app"
```

The script generates `dist/Phototropin.app` and `dist/Phototropin.zip`, then verifies the Apple Development signature, designated requirement, and ZIP integrity. It stops if no valid Apple Development certificate is available and never falls back to ad-hoc signing.

When exactly one certificate is available, its public fingerprint is pinned in the Git-ignored `Support/Signing.local` file. Future builds require the same certificate and stop instead of silently switching identities. If several certificates are present on first use, pass the exact 40-character SHA-1 certificate fingerprint for that invocation:

```sh
PHOTOTROPIN_SIGNING_IDENTITY_HASH=0123456789ABCDEF0123456789ABCDEF01234567 \
  ./scripts/build-app.sh
```

Do not store private keys or `.p12` and `.cer` files in the repository. The root `.gitignore` excludes certificates, private keys, App Store Connect keys, local signing configuration, `.env` files, keychains, and build products. Publishing the source does not publish the author or user's signing identity.

To intentionally replace an expired or revoked certificate, remove `Support/Signing.local` and build again to pin the new certificate. macOS may require screen-recording permission to be granted again after this identity change.

Before publishing, run:

```sh
./scripts/check-public-safety.sh
```

This checks only files that Git would publish. It verifies that credentials and machine-local signing files are ignored and rejects personal home paths, email addresses, the current signing fingerprint, and Team IDs. The `Phototropin checks` GitHub Actions workflow runs the same safety check and `swift test` without using repository secrets.

The app intentionally keeps the legacy Bundle ID `dev.pome.vision`. Changing it would make macOS treat Phototropin as a different app and could invalidate existing screen-recording permission. The first signed build may require you to remove permission granted to an older ad-hoc build, launch the new app, and grant permission once. Subsequent builds retain the same Bundle ID and signing identity so macOS can track them consistently.

On first use, macOS may also ask for access to the screenshot destination, which is usually the Desktop. If standard screenshots are configured to copy only to the clipboard, automatic monitoring cannot detect them; use Phototropin's region-capture button instead.

## CLI verification

```sh
swift run phototropin-cli /path/to/problem.png
swift run phototropin-cli --ocr-only /path/to/problem.png
swift run phototropin-cli --text "Video - Example title"
swift run phototropin-cli --describe-text "Video - Example title"
swift run phototropin-cli --describe-image /path/to/photo.png image-capable-model-id
swift run phototropin-cli --dialogue-text $'Hello.\nHi. Nice to meet you.'
```

The CLI is intended for development diagnostics rather than normal use. `--text` supplies arbitrary OCR text without an image and reports whether the content-explanation action should be offered. `--describe-text` tests OCR-only explanation, `--describe-image` sends an image to a vision-capable model, and `--dialogue-text` tests inferred multi-speaker organization. If the model argument is omitted, the CLI uses the first LLM returned by LM Studio's `/api/v1/models` endpoint.

## Repository structure

- `Sources/ScreenshotAnswerCore/` contains OCR, prompt boundaries, the LM Studio OpenAI-compatible client, and the reusable processing pipeline. It does not depend on the AppKit UI.
- `Sources/ScreenshotAnswerApp/` contains the menu-bar interface, Phototropin branding, screenshot monitoring, region capture, answer overlays, ScreenCaptureKit system audio, SpeechTranscriber integration, settings, and clipboard behavior.
- `Sources/ScreenshotAnswerCLI/` contains the single-image diagnostic CLI.
- `Support/AppIcon.svg` is the editable source for the full-color Finder icon.
- `Tests/` covers reading order, loopback restrictions, prompt boundaries, LM Studio request shapes, overlays, transcripts, and pipeline behavior.
- `scripts/build-app.sh` selects a login-keychain Apple Development identity, rejects ad-hoc signing, builds the app bundle, and verifies its signature.
- `scripts/check-public-safety.sh` checks publishable files for credentials, personal paths, email addresses, and local signing identifiers.

## Current limitations

- Automatic monitoring only detects supported image extensions with recognized screenshot filename prefixes. Add OS-specific prefixes to `ScreenshotFileClassifier` when needed.
- Normal question answering relies on OCR. Automatic content explanation resizes the source image to a maximum of 1600 pixels, encodes it as JPEG, and supplies it as an OpenAI-compatible `image_url` data URL to a local vision model. Accuracy for diagrams, equations, and small details depends on the model.
- System audio is transcribed as the selected English or Japanese language. Rapid language switching and DRM-protected content may not be captured accurately.
- A Draft Model must be vocabulary-compatible with the main model. Some combinations provide no speedup or are rejected by LM Studio. Configure MTP and DSpark in LM Studio.
- Passing `swift test` or a CLI OCR check does not prove screenshot monitoring, permission prompts, overlays, audio capture, or the full GUI flow. Verify those paths by launching the signed `.app` before distributing a binary.
