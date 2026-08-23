import SwiftUI

struct AppRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            PawTheme.background.ignoresSafeArea()

            Group {
                switch model.selectedTab {
                case .home:
                    HomeView(store: model.petStore, selectedTab: $model.selectedTab)
                case .chat:
                    ChatView(petStore: model.petStore)
                case .run:
                    RunView(tracker: model.runTracker) {
                        await model.finishRun()
                    }
                case .collection:
                    CollectionView(store: model.petStore)
                }
            }
            .padding(.bottom, 72)

            PawTabBar(selection: $model.selectedTab)
        }
        .foregroundStyle(PawTheme.ink)
        .sheet(item: $model.completedRun) { summary in
            RunSummaryView(summary: summary, pet: model.petStore.snapshot) {
                model.completedRun = nil
                model.runTracker.reset()
                model.selectedTab = .home
            }
            .presentationDetents([.large])
        }
    }
}

private struct PawTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 19, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selection == tab ? PawTheme.adventureBlue : PawTheme.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 5)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
}

