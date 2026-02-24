import SwiftUI
import GRDB

// MARK: - Setup state

private enum ReflectionSetupState {
    case checking
    case notInstalled
    case pulling(progress: Double, status: String)
    case ready(context: ReflectionContext)
}

// MARK: - Main coordinator

/// Local-LLM focus coaching tab. Connects to Ollama at localhost:11434.
@MainActor
struct ReflectionView: View {
    let dbPool: DatabasePool?
    let appState: AppState

    @State private var setupState: ReflectionSetupState = .checking
    @State private var messages: [OllamaService.ChatMessage] = []
    @State private var streamingContent: String = ""
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var setupDone: Bool = false

    var body: some View {
        switch setupState {
        case .checking:
            ReflectionCheckingView()
                .task {
                    guard !setupDone else { return }
                    setupDone = true
                    await checkSetup()
                }
        case .notInstalled:
            ReflectionNotInstalledView()
        case .pulling(let progress, let status):
            ReflectionPullingView(progress: progress, status: status)
        case .ready(let context):
            ReflectionChatView(
                context: context,
                messages: messages,
                streamingContent: streamingContent,
                inputText: $inputText,
                isStreaming: isStreaming,
                onSend: { await sendMessage(context: context) }
            )
        }
    }

    // MARK: - Setup

    private func checkSetup() async {
        guard await OllamaService.isRunning() else {
            setupState = .notInstalled
            return
        }
        if !(await OllamaService.isModelInstalled(OllamaService.model)) {
            setupState = .pulling(progress: 0, status: "Starting download…")
            do {
                try await OllamaService.pullModel(OllamaService.model) { progress, status in
                    Task { @MainActor [self] in
                        setupState = .pulling(progress: progress, status: status)
                    }
                }
            } catch {
                setupState = .notInstalled
                return
            }
        }
        guard let dbPool else {
            setupState = .notInstalled
            return
        }
        let modeName = appState.currentMode.displayName
        do {
            let context = try await dbPool.read { db in
                try ReflectionContextBuilder.build(db: db, currentModeName: modeName)
            }
            setupState = .ready(context: context)
        } catch {
            setupState = .notInstalled
        }
    }

    // MARK: - Chat

    private func sendMessage(context: ReflectionContext) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""
        let userMsg = OllamaService.ChatMessage(role: "user", content: text)
        messages.append(userMsg)
        streamingContent = ""
        isStreaming = true
        do {
            try await OllamaService.chat(
                model: OllamaService.model,
                messages: messages,
                system: context.systemPrompt
            ) { token in
                Task { @MainActor [self] in
                    streamingContent += token
                }
            }
            messages.append(OllamaService.ChatMessage(role: "assistant", content: streamingContent))
            streamingContent = ""
        } catch {
            streamingContent = ""
            messages.append(OllamaService.ChatMessage(
                role: "assistant",
                content: "Error: \(error.localizedDescription)"
            ))
        }
        isStreaming = false
    }
}

// MARK: - Checking view

struct ReflectionCheckingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Checking Ollama…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Not installed view

struct ReflectionNotInstalledView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)

                Text("Reflect — AI Focus Coach")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)

                Text("This tab uses a local AI model (llama3.2) that runs entirely on your Mac — no internet, no API keys, no cost. It knows your override patterns and session history.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Setup (one-time, ~2 min):")
                        .font(.subheadline.weight(.medium))

                    setupStep(n: 1, text: "Install Ollama from ollama.com")
                    setupStep(n: 2, text: "Run in Terminal: ollama serve")
                    setupStep(n: 3, text: "Return here — the model downloads automatically (~2 GB)")
                }
                .padding(12)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("Requires Ollama running at localhost:11434.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func setupStep(n: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n).")
                .font(.subheadline.weight(.medium))
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Pulling view

struct ReflectionPullingView: View {
    let progress: Double
    let status: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Downloading llama3.2…")
                .font(.title3.weight(.medium))

            ProgressView(value: progress)
                .frame(width: 200)

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chat view

struct ReflectionChatView: View {
    let context: ReflectionContext
    let messages: [OllamaService.ChatMessage]
    let streamingContent: String
    @Binding var inputText: String
    let isStreaming: Bool
    let onSend: () async -> Void

    @State private var showSystemPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            contextHeader
            Divider()
            if !context.hasEnoughData {
                notEnoughDataView
            } else {
                chatArea
                Divider()
                inputBar
            }
        }
    }

    private var contextHeader: some View {
        DisclosureGroup(
            "Context: \(context.overrideCount) overrides",
            isExpanded: $showSystemPrompt
        ) {
            Text(context.systemPrompt)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.3))
    }

    private var notEnoughDataView: some View {
        Text("Need at least 7 override attempts to unlock AI coaching. Keep using StayCell — this tab will unlock automatically.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        Text("Ask about your focus patterns, override triggers, or how to restructure your day. I have your real data.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(20)
                    }
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                        ChatBubble(message: msg)
                    }
                    if !streamingContent.isEmpty {
                        ChatBubble(message: OllamaService.ChatMessage(role: "assistant", content: streamingContent))
                            .id("streaming")
                    }
                    if isStreaming && streamingContent.isEmpty {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Thinking…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .id("thinking")
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: streamingContent) {
                withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
            }
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about your patterns…", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .onSubmit { Task { await onSend() } }

            Button {
                Task { await onSend() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming)
        }
        .padding(12)
    }
}

// MARK: - Chat bubble

struct ChatBubble: View {
    let message: OllamaService.ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
    }
}
