import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var healthKit: HealthKitService
    @ObservedObject var history: WorkoutHistoryStore
    var onDeleteJournal: (() -> Bool)?
    var completionMessage: String?
    var onRetrySave: (() -> Void)?
    var everydayActivity: EverydayActivityService?
    var onSyncActivity: (() async -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isRenaming = false
    @State private var proposedName = ""
    @State private var isDeletingHistory = false
    @State private var isRequestingHealth = false

    var body: some View {
        NavigationStack {
            List {
                if let message = store.storageMessage ?? completionMessage {
                    Section("Companion storage") {
                        Text(message).font(.footnote)
                        Button("Try again") { store.reloadFromSharedStorage(); onRetrySave?() }
                    }
                }
                Section {
                    HStack(spacing: 16) {
                        AnimalPortraitView(pet: store.snapshot)
                            .frame(width: 60, height: 76)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.snapshot.lifeStage == .egg ? "Your mystery egg" : store.snapshot.name)
                                .font(.headline)
                            Text(store.snapshot.lifeStage == .egg ? "A little friend is on the way." : "\(store.snapshot.lifeStage.displayName) · \(store.snapshot.species.displayName)")
                                .font(.subheadline)
                                .foregroundStyle(PawTheme.inkSecondary)
                        }
                    }
                    Button {
                        proposedName = store.snapshot.name
                        isRenaming = true
                    } label: {
                        Label("Name your companion", systemImage: "pencil")
                    }
                    NavigationLink { CompanionGuideView() } label: {
                        Label("Companion guide", systemImage: "book")
                    }
                    NavigationLink { WorkoutHistoryView(history: history) } label: {
                        Label("Workout journal", systemImage: "figure.walk.circle")
                    }
                } header: { Text("You and your companion") }
                .listRowBackground(PawTheme.surface)

                if let everydayActivity {
                    Section {
                        NavigationLink {
                            EverydayActivityView(service: everydayActivity, sync: { await onSyncActivity?() })
                        } label: {
                            Label("Everyday activity", systemImage: "figure.walk")
                        }
                    } footer: {
                        Text("Optionally count steps and workouts shared with Apple Health.")
                    }
                    .listRowBackground(PawTheme.surface)
                }

                Section {
                    Button {
                        isRequestingHealth = true
                        Task {
                            await healthKit.requestAuthorization()
                            isRequestingHealth = false
                        }
                    } label: {
                        HStack {
                            Label("Review Health access", systemImage: "heart")
                            Spacer()
                            if isRequestingHealth { ProgressView() }
                        }
                    }
                    .disabled(isRequestingHealth)
                    Text(healthAccessDescription)
                        .font(.footnote)
                        .foregroundStyle(PawTheme.inkSecondary)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label("Open iPhone Settings", systemImage: "gearshape")
                    }
                    NavigationLink { PrivacyView() } label: {
                        Label("Privacy and your data", systemImage: "hand.raised")
                    }
                } header: { Text("Permissions and privacy") }
                footer: {
                    Text("Location helps measure outdoor distance and route. The workout timer works without location. Manage Health categories in Health → your profile → Apps → PawPace.")
                }
                .listRowBackground(PawTheme.surface)

                Section {
                    Button(role: .destructive) { isDeletingHistory = true } label: {
                        Label("Delete workout journal", systemImage: "trash")
                    }
                    .disabled(history.workouts.isEmpty && history.storageMessage == nil)
                    if let message = history.storageMessage {
                        Text(message).font(.footnote).foregroundStyle(PawTheme.inkSecondary)
                    }
                } header: { Text("On this iPhone") }
                footer: { Text("Deletes only the journal on this device. Your companion, earned rewards, and Apple Health workouts stay in place.") }
                .listRowBackground(PawTheme.surface)

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Account", value: "Optional for friends & clubs")
                } header: { Text("PawPace") }
                .listRowBackground(PawTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(PawTheme.background.ignoresSafeArea())
            .foregroundStyle(PawTheme.ink)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Name your companion", isPresented: $isRenaming) {
                TextField("Companion name", text: $proposedName)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) { }
                Button("Save") { store.rename(to: proposedName) }
                    .disabled(PetName.normalized(proposedName) == nil)
            } message: {
                Text("Choose a name of up to 24 characters. Your name will appear after your egg hatches.")
            }
            .confirmationDialog("Delete your workout journal?", isPresented: $isDeletingHistory, titleVisibility: .visible) {
                Button("Delete journal", role: .destructive) {
                    if let onDeleteJournal { _ = onDeleteJournal() } else { history.deleteAll() }
                }
            } message: {
                Text("This permanently removes the workout summaries saved on this iPhone. Your companion’s progress and Apple Health records won’t change.")
            }
        }
        .tint(PawTheme.adventureBlue)
    }

    private var healthAccessDescription: String {
        switch healthKit.authorizationState {
        case .notRequested:
            "Choose which Health categories PawPace may use. Workouts, distance, and active energy can be saved; available heart rate readings can be shown during a workout."
        case .unavailable:
            "Apple Health is unavailable on this device. You can still use the workout timer and grow your companion."
        case .authorized:
            "Your permission request completed. Apple keeps your choices private: a completed request doesn’t mean every category was allowed. Review or change them in the Health app."
        case .denied:
            "The Health permission request couldn’t complete. You can try again or review PawPace in the Health app. The workout timer remains available."
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your movement.\nYour little world.")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("Buddy and Planner work without an account. Friends and clubs are optional and use Sign in with Apple. You choose which activity days and workout results to share. PawPace has no advertising or analytics service.")
                    .foregroundStyle(PawTheme.inkSecondary)
                GuideRow(symbol: "iphone", title: "What stays on your devices", detail: "Your companion’s name, appearance, genes, growth, movement totals, and rewards are saved on your device. Your paired Apple Watch receives companion and workout updates. Widgets can read the shared companion snapshot.")
                GuideRow(symbol: "book.closed", title: "Your workout journal", detail: "Saved summaries include workout type, dates, active time, distance, available heart rate and energy readings, and earned XP. The journal, interrupted-workout checkpoints, and pending Health save records stay in protected app storage excluded from backups. Deleting it in Settings doesn’t erase companion progress or Apple Health records.")
                GuideRow(symbol: "calendar", title: "Plans and memory photos", detail: "Personal plans, reminders and memory-book photos stay on this iPhone in protected storage excluded from backups. Selected photos are resized and their original metadata is removed. They are never uploaded to Club. Removing a memory photo leaves your photo library unchanged.")
                GuideRow(symbol: "person.3", title: "Optional private clubs", detail: "The Club service stores your Apple account identifier, a generated alias, club memberships, group plans and chosen encouragements. It doesn’t request your name or email. If you turn activity sharing on for a club, five credited movement minutes can contribute one dated activity day when you open PawPace. Members can see the date and alias; this club-day feature uploads no workout details, routes, measurements or companion identities.")
                GuideRow(symbol: "person.2", title: "Friends and your activity feed", detail: "Friends connect using a private code and an accepted request. A post contains your generated alias, activity, workout date, active duration and distance only if you choose it. Only friends connected before you shared the post can see it. The feed shows up to 100 posts from the last 30 days; posts stay on the service until you remove them or delete your account. Routes, heart rate, calories, photos and pet identities are never posted. Remove a post from its menu, or remove or block a friend in Club → Friends. Changes reach other devices after syncing.")
                GuideRow(symbol: "hand.raised", title: "Control your Club data", detail: "Activity sharing starts off in every club. Turning it off stops new contributions; Remove my shared days also deletes your earlier contributions from that club. Leaving removes your membership, days and encouragements there. Club → Account → Delete Club account removes your service account, friendships and posts and closes clubs you host. Your local Buddy, Planner and Apple Health records remain. Signing out removes the local Club cache and unsent actions, but does not delete your service account.")
                GuideRow(symbol: "heart", title: "Apple Health is your choice", detail: "With your permission, PawPace reads relevant workout, distance, active energy, and heart rate data and saves workouts, distance, and energy to Apple Health. Apple Health keeps its own copies under your Health and iCloud settings. Everyday activity is optional and reads steps and new workouts only after you enable it. It refreshes when you open the app or choose Sync now. Imported workouts aren’t written back. PawPace doesn’t use Health data for advertising or sell it.")
                GuideRow(symbol: "square.and.arrow.up", title: "You choose what to share", detail: "Sharing cards stay on your device until you use the system share sheet. You preview the exact card and choose whether to reveal your companion or include activity minutes. Cards never contain routes, heart rate, or other Health readings.")
                GuideRow(symbol: "location", title: "Location during outdoor workouts", detail: "Location is used during an active outdoor distance workout to estimate distance and pace. The recorded route appears in your finish summary, with start and finish marked. Tracking stops when you pause or finish. The route is kept only for that recap; it isn’t included in the saved journal or share cards and isn’t sent to a PawPace server.")
                GuideRow(symbol: "slider.horizontal.3", title: "You control access and retention", detail: "You can change location access in iPhone Settings and Health access in the Health app. You can delete the local journal at any time. Companion and workout files are excluded from system backups. General app preferences may be included. To remove workouts from Apple Health, manage PawPace’s data in the Health app.")
                Text("This information describes the app installed on your device. No sign-in, payment, or cloud service is needed to care for your companion.")
                    .font(.footnote)
                    .foregroundStyle(PawTheme.inkSecondary)
            }
            .padding(24)
        }
        .background(PawTheme.background.ignoresSafeArea())
        .foregroundStyle(PawTheme.ink)
        .navigationTitle("Privacy and your data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
