import AVFoundation
import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Sender: Equatable {
        case user
        case pet
    }

    let id = UUID()
    let sender: Sender
    let text: String
    let date: Date
}

protocol CompanionChatService {
    func reply(to message: String, pet: PetSnapshot) async -> String
}

struct LocalCompanionChatService: CompanionChatService {
    func reply(to message: String, pet: PetSnapshot) async -> String {
        try? await Task.sleep(for: .milliseconds(450))
        let lowercased = message.lowercased()

        if lowercased.contains("run") || lowercased.contains("walk") {
            return pet.energy < 30
                ? "I want to go, but my energy is low. Feed me first and I’ll be trail-ready!"
                : "Yes! A gentle 3 km quest would earn us XP, coins, and possibly a new trail item."
        }
        if lowercased.contains("how are") || lowercased.contains("feel") {
            return "I’m feeling \(pet.mood.label.lowercased()) with \(pet.energy)% energy. Friendship is at \(pet.friendship)%—that part makes my tail glow."
        }
        if lowercased.contains("story") {
            return "Once, a tiny trail creature followed a blue firefly for twelve kilometers. The firefly was lost. The creature pretended the whole thing was a quest."
        }
        if lowercased.contains("evolve") {
            if let nextStage = pet.nextStage {
                return "My next form is \(nextStage.displayName) at level \(nextStage.minimumLevel). Every real run brings us closer."
            }
            return "I’ve reached my final form, but our friendship can still grow forever."
        }
        return "I’m listening. Tell me more—and if it involves a trail, snacks, or mysterious treasure, I’m already interested."
    }
}

@MainActor
final class CompanionChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage]
    @Published var draft = ""
    @Published private(set) var isReplying = false

    private let service: CompanionChatService
    private let petStore: PetStore
    private let synthesizer = AVSpeechSynthesizer()

    init(petStore: PetStore, service: CompanionChatService = LocalCompanionChatService()) {
        self.petStore = petStore
        self.service = service
        self.messages = [
            ChatMessage(sender: .pet, text: "Good morning! My paws are tingling. Did you sleep well?", date: .now),
            ChatMessage(sender: .pet, text: "We have 1.2 km left on today’s quest.", date: .now)
        ]
    }

    func send(_ suggestedText: String? = nil) {
        let text = (suggestedText ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isReplying else { return }

        draft = ""
        messages.append(ChatMessage(sender: .user, text: text, date: .now))
        isReplying = true

        Task {
            let reply = await service.reply(to: text, pet: petStore.snapshot)
            messages.append(ChatMessage(sender: .pet, text: reply, date: .now))
            isReplying = false
        }
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.08
        synthesizer.speak(utterance)
    }
}
