import SwiftUI

struct EverydayActivityView: View {
    @ObservedObject var service: EverydayActivityService
    var sync: () async -> Void

    var body: some View {
        List {
            Section {
                Toggle("Count everyday activity", isOn: Binding(get: { service.isEnabled }, set: { enabled in
                    Task {
                        await service.setEnabled(enabled)
                        if service.isEnabled { await sync() }
                    }
                }))
                .disabled(service.isSyncing)
                Text("With your permission, steps and workouts shared with Apple Health count toward growth, weekly adventures, and new discoveries. No PawPace workout timer is needed.")
                    .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
            } header: { Text("A little movement adds up") }
            .listRowBackground(PawTheme.surface)

            Section {
                GuideRow(symbol: "figure.walk", title: "Steps become progress", detail: "100 steps earn one progress minute. This is a game rule, not a measurement of exercise time. Step progress shapes the Endurance trait while your pet grows.")
                GuideRow(symbol: "checkmark.shield", title: "One daily allowance", detail: "We use the larger of your workout minutes or step progress each day, up to 60 minutes. They aren’t added together. Copied workouts with overlapping times don’t earn twice.")
                GuideRow(symbol: "calendar", title: "Start from here", detail: "Only activity recorded after you turn this on is imported. Opening PawPace or tapping Sync now checks the last seven days for delayed uploads. Earlier history stays in Health.")
                GuideRow(symbol: "hand.raised", title: "Always your choice", detail: "Turn this off at any time and keep earned progress. Review read access in Health → your profile → Apps → PawPace. Empty results can mean no shared activity or no read permission.")
            }
            .listRowBackground(PawTheme.surface)

            Section {
                Button {
                    Task { await sync() }
                } label: {
                    HStack {
                        Label("Sync now", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        Spacer()
                        if service.isSyncing { ProgressView() }
                    }
                }
                .disabled(!service.isEnabled || service.isSyncing)
                if let date = service.lastSynced { LabeledContent("Last checked", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if let message = service.message { Text(message).font(.footnote).foregroundStyle(PawTheme.inkSecondary) }
                Text("Finish an active PawPace workout before syncing. Imported workouts are never written back to Health. They may appear in your local journal.")
                    .font(.footnote).foregroundStyle(PawTheme.inkSecondary)
            }
            .listRowBackground(PawTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(PawTheme.background)
        .navigationTitle("Everyday activity")
        .navigationBarTitleDisplayMode(.inline)
        .tint(PawTheme.adventureBlue)
    }
}
