import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case chat
    case run
    case collection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .chat: "Chat"
        case .run: "Run"
        case .collection: "Collect"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .chat: "message.fill"
        case .run: "figure.run"
        case .collection: "square.grid.2x2.fill"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var completedRun: RunSummary?

    let petStore: PetStore
    let healthKit: HealthKitService
    let runTracker: RunTracker

    init() {
        let petStore = PetStore()
        let healthKit = HealthKitService()
        self.petStore = petStore
        self.healthKit = healthKit
        self.runTracker = RunTracker(healthKit: healthKit, petName: petStore.snapshot.name)
    }

    func handle(url: URL) {
        guard url.scheme == "pawpace" else { return }
        switch url.host {
        case "chat": selectedTab = .chat
        case "run": selectedTab = .run
        case "collection": selectedTab = .collection
        default: selectedTab = .home
        }
    }

    func finishRun() async {
        guard let summary = await runTracker.finish() else { return }
        petStore.applyRun(summary)
        completedRun = summary
    }
}
