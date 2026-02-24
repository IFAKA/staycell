import SwiftUI
import GRDB
import os.log

/// Override gate: requires typing a phrase to unlock blocked content.
/// Paste disabled. 30-second minimum. Escalation on repeated overrides.
struct OverrideGateView: View {
    let overrideLevel: Int // 1st, 2nd, 3rd attempt today
    let onGranted: () -> Void
    let onCancelled: () -> Void

    @State private var typedText = ""
    @State private var elapsedSeconds = 0
    @State private var timerRunning = false
    @State private var phraseIndex: Int

    private let creamColor = Color(red: 0.96, green: 0.93, blue: 0.85)
    private let subtleColor = Color(red: 0.5, green: 0.48, blue: 0.42)

    private var targetPhrase: String {
        OverridePhrases.pool[phraseIndex % OverridePhrases.pool.count]
    }

    private var minimumWaitSeconds: Int {
        switch overrideLevel {
        case 1: TimerDurations.overrideMinimumSeconds       // 30s
        case 2: TimerDurations.overrideMinimumSeconds * 2   // 60s
        default: TimerDurations.overrideMinimumSeconds * 5  // 150s (2.5 min)
        }
    }

    private var canSubmit: Bool {
        elapsedSeconds >= minimumWaitSeconds &&
        typedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
            targetPhrase.lowercased()
    }

    init(overrideLevel: Int, onGranted: @escaping () -> Void, onCancelled: @escaping () -> Void) {
        self.overrideLevel = overrideLevel
        self.onGranted = onGranted
        self.onCancelled = onCancelled
        // Rotate phrase based on current date + level to avoid repetition
        let dayIndex = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        self._phraseIndex = State(initialValue: (dayIndex + overrideLevel) % OverridePhrases.pool.count)
    }

    var body: some View {
        ZStack {
            Color(red: 0.051, green: 0.051, blue: 0.051)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Level indicator
                if overrideLevel > 1 {
                    Text("Override attempt #\(overrideLevel)")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(subtleColor)
                }

                // Instructions
                Text("Type this phrase exactly to proceed:")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(creamColor.opacity(0.7))

                // Target phrase
                Text(targetPhrase)
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(creamColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // Text input (paste disabled via custom field)
                NoPasteTextField(text: $typedText, placeholder: "Type here...")
                    .frame(width: 500, height: 36)
                    .padding(.horizontal, 40)

                // Timer
                if elapsedSeconds < minimumWaitSeconds {
                    Text("Wait \(minimumWaitSeconds - elapsedSeconds) more seconds...")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(subtleColor)
                }

                // Match indicator
                if !typedText.isEmpty {
                    let matches = typedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
                        targetPhrase.lowercased()
                    Text(matches ? "Phrase matches." : "Keep typing...")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(matches ? creamColor.opacity(0.7) : subtleColor)
                }

                HStack(spacing: 20) {
                    Button("Cancel") {
                        onCancelled()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(subtleColor)
                    .font(.system(size: 14, design: .serif))

                    if overrideLevel >= 3 {
                        Button("Disable blocking for today") {
                            onGranted()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(subtleColor.opacity(0.5))
                        .font(.system(size: 12, design: .serif))
                    }

                    Button("Override (\(TimerDurations.overrideTimedAccessMinutes) min)") {
                        onGranted()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSubmit ? creamColor : subtleColor.opacity(0.3))
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .disabled(!canSubmit)
                }

                Spacer()
            }
        }
        .onAppear {
            startTimer()
        }
    }

    private func startTimer() {
        timerRunning = true
        Task { @MainActor in
            while elapsedSeconds < minimumWaitSeconds * 2 {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }
    }
}

/// A text field that disables paste operations.
struct NoPasteTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NoPasteNSTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 16)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        field.textColor = NSColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

/// NSTextField subclass that blocks paste.
final class NoPasteNSTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Block Cmd+V (paste)
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            return true // Consume the event
        }
        return super.performKeyEquivalent(with: event)
    }
}
