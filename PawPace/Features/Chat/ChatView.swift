import SwiftUI

struct ChatView: View {
    @ObservedObject private var petStore: PetStore
    @StateObject private var viewModel: CompanionChatViewModel
    @StateObject private var voice = VoiceInputService()

    init(petStore: PetStore) {
        self.petStore = petStore
        _viewModel = StateObject(wrappedValue: CompanionChatViewModel(petStore: petStore))
    }

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            messages
            suggestions
            composer
        }
        .background(
            LinearGradient(
                colors: [PawTheme.background, PawTheme.adventureBlue.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear { voice.requestAuthorization() }
        .onChange(of: voice.transcript) { _, transcript in
            viewModel.draft = transcript
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 11) {
            MochiCreatureView(mood: petStore.snapshot.mood, stage: petStore.snapshot.stage)
                .frame(width: 48, height: 48)
                .padding(3)
                .background(PawTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(petStore.snapshot.name)
                    .font(.headline.weight(.bold))
                Text("\(petStore.snapshot.mood.label) · ready to chat")
                    .font(.caption)
                    .foregroundStyle(PawTheme.inkSecondary)
            }
            Spacer()
            Button {
                voice.toggle()
            } label: {
                Image(systemName: voice.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(voice.isRecording ? PawTheme.coralOrange : PawTheme.adventureBlue)
            }
            .accessibilityLabel(voice.isRecording ? "Stop voice input" : "Start voice input")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(PawTheme.surface.opacity(0.94))
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        ChatBubble(message: message) {
                            viewModel.speak(message.text)
                        }
                        .id(message.id)
                    }

                    if viewModel.isReplying {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.small)
                            Text("\(petStore.snapshot.name) is thinking…")
                                .font(.caption)
                        }
                        .foregroundStyle(PawTheme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(["Let’s run!", "Tell me a story", "How are you?", "When do you evolve?"], id: \.self) { suggestion in
                    Button(suggestion) { viewModel.send(suggestion) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PawTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(PawTheme.surface, in: Capsule())
                        .overlay { Capsule().stroke(PawTheme.line) }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 8)
    }

    private var composer: some View {
        HStack(spacing: 9) {
            TextField("Message \(petStore.snapshot.name)…", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(PawTheme.line) }
                .submitLabel(.send)
                .onSubmit { viewModel.send() }

            Button { viewModel.send() } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(PawTheme.adventureBlue, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let speak: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.sender == .user { Spacer(minLength: 52) }

            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(message.sender == .user ? .white : PawTheme.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(
                        message.sender == .user ? PawTheme.adventureBlue : PawTheme.surface,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )

                if message.sender == .pet {
                    Button(action: speak) {
                        Label("Speak", systemImage: "speaker.wave.2.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PawTheme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if message.sender == .pet { Spacer(minLength: 52) }
        }
    }
}

