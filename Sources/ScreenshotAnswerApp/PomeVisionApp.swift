import AppKit
import ScreenshotAnswerCore
import SwiftUI

@main
struct PomeVisionApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PomeVisionPanel(model: model)
        } label: {
            PomeVisionMenuBarIcon(isRecording: model.isListeningToSystemAudio)
                .accessibilityLabel("Pome Vision")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct PomeVisionPanel: View {
    @ObservedObject var model: AppModel
    @State private var isRecognizedTextExpanded = false
    @State private var isAnswerExpanded = false
    @State private var isGenerationDetailsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.status)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
            }

            HStack {
                Button("範囲を撮影して回答", systemImage: "viewfinder") {
                    model.captureSelection()
                }
                .keyboardShortcut("4", modifiers: [.control, .option, .command])
                .disabled(model.isBusy)

                Button("再確認", systemImage: "arrow.clockwise") {
                    model.scanNow()
                }
                .help("保存先を今すぐ再確認")
            }

            GroupBox("LM Studioモデル") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("", selection: $model.selectedModel) {
                            if model.availableModels.isEmpty {
                                Text("モデルなし").tag("")
                            }
                            ForEach(model.availableModels, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                        Button("更新") { Task { await model.refreshModels() } }
                    }

                    DisclosureGroup(
                        "高速化の詳細",
                        isExpanded: $isGenerationDetailsExpanded
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("方式", selection: $model.speculativeDecodingMode) {
                                ForEach(SpeculativeDecodingMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }

                            if model.speculativeDecodingMode == .draftModel {
                                Picker("Draft Model", selection: $model.selectedDraftModel) {
                                    if model.availableDraftModels.isEmpty {
                                        Text("互換モデルなし").tag("")
                                    }
                                    ForEach(model.availableDraftModels, id: \.self) {
                                        Text($0).tag($0)
                                    }
                                }
                                .disabled(model.availableDraftModels.isEmpty)

                                Text("メインモデルと語彙が互換する、小さいモデルを選んでください。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text("MTP / DSparkはモデル読込時の機能です。ここではLM Studio側で読み込んだ設定をそのまま使用します。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 5)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(4)
            }

            Toggle("標準スクリーンショットを自動検出", isOn: $model.monitorsScreenshots)
            Toggle("回答を画面左下に表示", isOn: $model.showsAnswerPopup)
            Toggle("生成した回答を自動コピー", isOn: $model.copiesAnswer)

            GroupBox("今流れている音声") {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Picker("言語", selection: $model.systemAudioLanguage) {
                            ForEach(SystemAudioLanguage.allCases) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        .frame(width: 150)

                        Spacer()

                        if model.isListeningToSystemAudio {
                            Label(model.systemAudioElapsedText, systemImage: "record.circle.fill")
                                .foregroundStyle(.red)
                                .monospacedDigit()
                        }
                    }

                    TextField(
                        "例: 話者は何を主張していますか？",
                        text: $model.audioQuestion
                    )
                    .textFieldStyle(.roundedBorder)

                    Toggle(
                        "複数話者を対話として整理（推定）",
                        isOn: $model.organizesMultipleSpeakers
                    )

                    HStack {
                        if model.isListeningToSystemAudio {
                            Button("停止して回答", systemImage: "stop.circle.fill") {
                                model.stopSystemAudioAndAnswer()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button("音声を聞く", systemImage: "ear") {
                                model.startSystemAudioListening()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy || !model.supportsSystemAudioListening)
                        }

                        if !model.audioTranscript.isEmpty && !model.isListeningToSystemAudio {
                            Button("この音声に質問", systemImage: "bubble.left.and.text.bubble.right") {
                                model.answerAboutCapturedAudio()
                            }
                            .disabled(model.isBusy)
                        }
                    }

                    if !model.supportsSystemAudioListening {
                        Text("macOS 26以降で利用できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !model.audioTranscript.isEmpty {
                        ScrollView {
                            Text(model.audioTranscript)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 80)
                    } else {
                        Text("最大90秒。音声は保存せず、文字起こし後に破棄します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(5)
            }

            if !model.recognizedText.isEmpty {
                CollapsibleSection(
                    title: "認識した問題",
                    isExpanded: $isRecognizedTextExpanded
                ) {
                    GroupBox {
                        ScrollView {
                            Text(model.recognizedText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 110)
                        .padding(6)
                    }
                }
            }

            if !model.answer.isEmpty {
                CollapsibleSection(title: "回答", isExpanded: $isAnswerExpanded) {
                    GroupBox {
                        ScrollView {
                            Text(model.answer)
                                .font(.body.weight(.medium))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(6)
                    }
                }

                HStack {
                    if model.canDescribeRecognizedContent {
                        Button("これは何？ 内容を説明", systemImage: "questionmark.bubble") {
                            model.describeRecognizedContent()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("回答をコピー", systemImage: "doc.on.doc") { model.copyAnswer() }
                }
            }

            Divider()

            HStack {
                Button("保存先を開く") { model.openScreenshotDirectory() }
                Spacer()
                Button("終了") { NSApplication.shared.terminate(nil) }
            }
            }
            .padding(14)
        }
        // MenuBarExtra(.window) can collapse a root ScrollView to almost zero
        // when it only has a maximum height. Keep the popover itself at a
        // stable size and let the contents scroll inside it.
        .frame(width: 430, height: 650)
        .onChange(of: model.recognizedText) { _, _ in
            isRecognizedTextExpanded = false
        }
        .onChange(of: model.answer) { _, _ in
            isAnswerExpanded = false
        }
    }
}

private struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(title)
                        .font(.headline)

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary.opacity(isHovering ? 0.62 : 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .accessibilityValue(isExpanded ? "展開中" : "折りたたみ中")
            .accessibilityHint(isExpanded ? "クリックして折りたたみます" : "クリックして展開します")

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
