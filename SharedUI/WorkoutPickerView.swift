import SwiftUI

/// One searchable activity catalog is shared by the phone and Watch.
struct WorkoutPickerView: View {
    let selection: WorkoutActivity
    let onSelect: (WorkoutActivity) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var activities: [WorkoutActivity] {
        WorkoutActivity.search(search)
    }

    private var categories: [String] {
        Array(Set(activities.map { $0.category.displayName })).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                if activities.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    ForEach(categories, id: \.self) { category in
                        Section(category) {
                            ForEach(activities.filter { $0.category.displayName == category }) { activity in
                                Button {
                                    onSelect(activity)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: activity.symbol)
                                            .font(.title3)
                                            .foregroundStyle(PawTheme.adventureBlue)
                                            .frame(width: 30)
                                        Text(activity.displayName)
                                            .foregroundStyle(PawTheme.ink)
                                        Spacer()
                                        if selection == activity {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(PawTheme.adventureBlue)
                                        }
                                    }
                                    .padding(.vertical, 7)
                                }
                                .accessibilityAddTraits(selection == activity ? .isSelected : [])
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Workouts")
            .searchable(text: $search, prompt: "Find a workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(PawTheme.adventureBlue)
    }
}
