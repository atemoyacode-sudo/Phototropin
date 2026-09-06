import AppKit
import QuartzCore
import ScreenshotAnswerCore
import SwiftUI

@MainActor
final class AnswerOverlayWindowController {
    private let popupSize = CGSize(width: 430, height: 210)
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var dismissAfter: TimeInterval = 20

    func show(
        answer: String,
        recognizedText: String,
        language: InterfaceLanguage,
        dismissAfter: TimeInterval = 20,
        onExplain: (() -> Void)? = nil,
        onAsk: ((String) -> Void)? = nil,
        onCopy: @escaping () -> Void
    ) {
        dismissTask?.cancel()
        self.dismissAfter = dismissAfter

        let targetScreen = OverlayWindowSupport.targetScreen()
        guard let targetScreen else { return }

        let panel = panel ?? OverlayWindowSupport.makePanel(
            contentSize: popupSize,
            transient: true
        )
        self.panel = panel

        panel.contentView = NSHostingView(
            rootView: AnswerOverlayCard(
                answer: answer,
                recognizedText: recognizedText,
                language: language,
                onExplain: onExplain,
                onAsk: onAsk,
                onCopy: onCopy,
                onClose: { [weak self] in self?.dismiss() },
                onInteractionChanged: { [weak self] isInteracting in
                    self?.setInteracting(isInteracting)
                },
                onActivate: { [weak self] in self?.activateForInput() }
            )
        )

        let finalFrame = AnswerOverlayPlacement.frame(
            in: targetScreen.visibleFrame,
            popupSize: popupSize
        )
        var initialFrame = finalFrame
        initialFrame.origin.y -= 14
        panel.setFrame(initialFrame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }

        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            guard let self else { return }
            let nanoseconds = UInt64(max(0, self.dismissAfter) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    /// Brings the menu-bar app forward so the follow-up field can receive
    /// keystrokes. Only an explicit click reaches here, never a hover, so the
    /// card still never steals focus on its own.
    private func activateForInput() {
        setInteracting(true)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Holds the card open while the follow-up bar is in use. A card that
    /// vanishes mid-question would be worse than having no question bar.
    private func setInteracting(_ isInteracting: Bool) {
        if isInteracting {
            dismissTask?.cancel()
            dismissTask = nil
        } else {
            scheduleDismiss()
        }
    }

    func showFailure(_ message: String, language: InterfaceLanguage) {
        show(
            answer: message,
            recognizedText: language.text(
                "回答を生成できませんでした",
                "The answer could not be generated"
            ),
            language: language,
            dismissAfter: 20,
            onCopy: {}
        )
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel, panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    func dismissImmediately() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.alphaValue = 0
        panel?.orderOut(nil)
    }

}

private struct AnswerOverlayCard: View {
    let answer: String
    let recognizedText: String
    let language: InterfaceLanguage
    let onExplain: (() -> Void)?
    let onAsk: ((String) -> Void)?
    let onCopy: () -> Void
    let onClose: () -> Void
    let onInteractionChanged: (Bool) -> Void
    let onActivate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text("Phototropin")
                    .font(.headline)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help(language.text("回答をコピー", "Copy answer"))
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help(language.text("閉じる", "Close"))
            }

            Text(recognizedText.replacingOccurrences(of: "\n", with: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            ScrollView {
                Text(AnswerTextFormatter.attributed(answer))
                    .font(.body.weight(.medium))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                if let onExplain {
                    Button(language.text("これは何？ 内容を説明", "What Is This? Explain"), systemImage: "questionmark.bubble") {
                        onClose()
                        onExplain()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let onAsk {
                    AnswerFollowUpBar(
                        language: language,
                        onAsk: onAsk,
                        onInteractionChanged: onInteractionChanged,
                        onActivate: onActivate
                    )
                }
            }
        }
        .padding(16)
        .frame(width: 430, height: 210)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }
}

/// A collapsed dot that opens into a question field on hover.
///
/// The card is only 430×210, so a permanently visible input would crowd out the
/// answer itself. The dot stays visible rather than appearing after a scroll,
/// so it can be found without knowing it is there.
private struct AnswerFollowUpBar: View {
    let language: InterfaceLanguage
    let onAsk: (String) -> Void
    let onInteractionChanged: (Bool) -> Void
    let onActivate: () -> Void

    @State private var isExpanded = false
    @State private var question = ""
    @FocusState private var isFocused: Bool

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var placeholder: String {
        language.text("この内容について質問", "Ask about this")
    }

    var body: some View {
        HStack(spacing: 6) {
            if isExpanded {
                TextField(placeholder, text: $question)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($isFocused)
                    .onSubmit(submit)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                    .simultaneousGesture(TapGesture().onEnded { onActivate() })

                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(trimmedQuestion.isEmpty)
                .help(placeholder)
            } else {
                Spacer(minLength: 0)

                Button(action: expandForClick) {
                    Image(systemName: "bubble.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(.quaternary, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(placeholder)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isExpanded)
        .onHover { isHovering in
            if isHovering {
                isExpanded = true
            } else if trimmedQuestion.isEmpty, !isFocused {
                isExpanded = false
            }
            onInteractionChanged(isHovering || isExpanded)
        }
    }

    /// Hover only opens the bar. A click also brings the app forward, which is
    /// what actually lets the field accept keystrokes.
    private func expandForClick() {
        isExpanded = true
        onActivate()
        isFocused = true
    }

    private func submit() {
        let question = trimmedQuestion
        guard !question.isEmpty else { return }
        self.question = ""
        isExpanded = false
        isFocused = false
        onInteractionChanged(false)
        onAsk(question)
    }
}
