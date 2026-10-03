import SwiftUI

struct ClubDetailView: View {
    @ObservedObject var store: ClubStore
    @ObservedObject var planner: PlannerStore
    @ObservedObject var petStore: PetStore
    let clubID: String
    @State private var schedulesEvent = false
    @State private var confirmsSharing = false
    @State private var destructiveAction: ClubDestructiveAction?
    @State private var planMessage: String?
    private var club: RunningClub? { store.clubs.first { $0.id == clubID } }
    private var userID: String { store.session?.account.id ?? "" }

    var body: some View {
        ScrollView {
            if let club {
                VStack(alignment: .leading, spacing: 24) {
                    ClubCampsiteView(level: club.campLevel)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(club.campTitle).font(.system(.title2, design: .rounded, weight: .bold))
                        Text("\(club.totalDays) activity days shared together")
                            .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                    }
                    weeklyGoal(club)
                    activitySharing(club)
                    groupActivities(club)
                    members(club)
                    if !club.cheers.isEmpty { encouragement(club) }
                    if club.ownerID == userID {
                        Button("Invite or replace invitation", systemImage: "envelope.badge") {
                            _ = store.enqueue(ClubCommand(action: "invite", clubID: clubID))
                        }.buttonStyle(.bordered)
                        Button("Close club", role: .destructive) { destructiveAction = .close }
                            .frame(minHeight: 44)
                    } else {
                        Button("Leave club", role: .destructive) { destructiveAction = .leave }
                            .frame(minHeight: 44)
                    }
                    if let message = store.message ?? planner.storageMessage { Text(message).font(.footnote).foregroundStyle(PawTheme.inkSecondary) }
                    if store.pending.contains(where: { $0.command.clubID == clubID }) {
                        Label("Changes are waiting to sync. Review them on the Club tab.", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote).foregroundStyle(PawTheme.inkSecondary)
                    }
                }.padding(22)
            } else {
                ContentUnavailableView("This club isn’t available", systemImage: "person.2.slash",
                    description: Text("It may have closed, or your membership may have changed. Return to Club to sync or join another."))
            }
        }
        .background(PawTheme.background).foregroundStyle(PawTheme.ink).tint(PawTheme.adventureBlue)
        .navigationTitle(club.map { ClubPrivacy.title($0.name, pet: petStore.snapshot) } ?? "Club")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PawTheme.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .refreshable { await store.refresh() }
        .sheet(isPresented: $schedulesEvent) { ClubEventEditor(store: store, clubID: clubID) }
        .confirmationDialog("Share activity days with this club?", isPresented: $confirmsSharing, titleVisibility: .visible) {
            Button("Share today and future activity days") { store.setSharing(true, clubID: clubID) }
        } message: {
            Text("When today reaches five credited movement minutes, PawPace can share one activity day under your Club alias. Other members can see the day. Workout records, routes and measurements stay private. Earlier days won’t be uploaded. You can turn this off or remove your shared days here.")
        }
        .confirmationDialog(destructiveAction?.title ?? "", isPresented: Binding(get: { destructiveAction != nil }, set: { if !$0 { destructiveAction = nil } }), titleVisibility: .visible) {
            if let action = destructiveAction {
                Button(action.button, role: .destructive) {
                    switch action {
                    case .erase: store.eraseSharedDays(clubID: clubID)
                    case .leave: _ = store.enqueue(ClubCommand(action: "leave", clubID: clubID))
                    case .close: _ = store.enqueue(ClubCommand(action: "deleteClub", clubID: clubID))
                    case let .remove(id): _ = store.enqueue(ClubCommand(action: "removeMember", clubID: clubID, data: .init(memberID: id)))
                    case let .cancel(id): _ = store.enqueue(ClubCommand(action: "cancelEvent", clubID: clubID, data: .init(eventID: id)))
                    }
                    destructiveAction = nil
                }
            }
        } message: { Text(destructiveAction?.detail ?? "") }
    }

    private func weeklyGoal(_ club: RunningClub) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("This week, together", systemImage: "leaf").font(.headline)
            Text("\(club.weeklyDays) / \(club.weeklyTarget) activity days").font(.title2.bold())
            ProgressView(value: Double(min(club.weeklyDays, club.weeklyTarget)), total: Double(club.weeklyTarget))
            Text(club.weeklyDays >= club.weeklyTarget ? "Your club reached its gentle goal. Every little effort made room for this." : "Five credited movement minutes can add one day per friend. There’s room for everyone’s pace and for rest.")
                .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
            Text("Week of \(club.weekStart) · \(club.timeZone)").font(.caption).foregroundStyle(PawTheme.inkSecondary)
            Text("The garden grows at 5, 20 and 50 shared days across all weeks.").font(.caption)
        }.pawCard()
    }

    private func activitySharing(_ club: RunningClub) -> some View {
        let serverEnabled = club.members.first { $0.id == userID }?.sharesActivity ?? false
        let paused = store.archive?.sharingPaused.contains(club.id) ?? true
        let pending = store.pending.last { $0.command.clubID == clubID && $0.command.action == "sharing" }
        let enabled = (pending?.failure == nil ? pending?.command.data.enabled : nil) ?? (serverEnabled && !paused)
        return VStack(alignment: .leading, spacing: 12) {
            Toggle("Share my activity days", isOn: Binding(get: { enabled }, set: { value in
                if value { confirmsSharing = true } else { store.setSharing(false, clubID: clubID) }
            }))
            Text("Only today and future qualifying days while sharing is on. Open PawPace to sync. Your club sees an activity day, never the underlying workout or Health measurements.")
                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            if let pending {
                Text(pending.failure == nil ? "Your sharing preference is waiting to sync." : "Your sharing preference couldn’t sync. Review the unsent action on the Club screen.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }
            Button("Remove my shared days", role: .destructive) { destructiveAction = .erase }.frame(minHeight: 44)
        }.pawCard()
    }

    private func groupActivities(_ club: RunningClub) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Make a little plan", systemImage: "calendar").font(.headline)
            if club.events.isEmpty { Text("No group activities yet. Your host can make the first plan.").foregroundStyle(PawTheme.inkSecondary) }
            ForEach(club.events) { event in
                VStack(alignment: .leading, spacing: 8) {
                    Label(event.activity.displayName, systemImage: event.activity.symbol).font(.headline)
                    Text("\(event.scheduledAt.formatted(date: .abbreviated, time: .shortened)) · \(event.durationMinutes) min")
                        .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                    if event.cancelled {
                        Label("Cancelled by the host", systemImage: "xmark.circle").font(.subheadline)
                        Text("A copy already in your Planner remains your own plan. You can keep it or remove it there.").font(.caption)
                    } else {
                        let added = planner.plans.contains { $0.clubEventID == event.plannerID }
                        Button(added ? "In your Planner" : "Add to my Planner", systemImage: added ? "checkmark.circle" : "calendar.badge.plus") {
                            planMessage = planner.save(event.plan) ? "Added to your Planner." : planner.storageMessage
                        }.buttonStyle(.bordered).disabled(added || event.scheduledAt < .now)
                        if club.ownerID == userID {
                            Button("Cancel activity", role: .destructive) { destructiveAction = .cancel(event.id) }.frame(minHeight: 44)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            if club.ownerID == userID { Button("Plan a group activity", systemImage: "plus") { schedulesEvent = true }.buttonStyle(.bordered) }
            if let planMessage { Text(planMessage).font(.caption).accessibilityAddTraits(.updatesFrequently) }
            Text("Times appear in your phone’s time zone. Adding a plan never starts a workout or awards progress.")
                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
        }.pawCard()
    }

    private func members(_ club: RunningClub) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Around the campsite", systemImage: "person.2").font(.headline)
            ForEach(club.members) { member in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "leaf.circle.fill").font(.title).foregroundStyle(PawTheme.adventureBlue)
                        VStack(alignment: .leading) {
                            Text("\(member.alias)\(member.id == userID ? " · You" : "")").font(.subheadline.bold())
                            Text(member.id == club.ownerID ? "Club host" : "Club friend").font(.caption).foregroundStyle(PawTheme.inkSecondary)
                        }
                    }
                    let days = club.days.filter { $0.memberID == member.id }.count
                    Text("\(days) shared \(days == 1 ? "day" : "days") this week")
                        .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                    if member.id != userID {
                        Menu("Send encouragement", systemImage: "heart") {
                            ForEach(ClubCheerKind.allCases) { kind in
                                Button(kind.title, systemImage: kind.symbol) {
                                    _ = store.enqueue(ClubCommand(action: "cheer", clubID: clubID, data: .init(recipientID: member.id, kind: kind)))
                                }
                            }
                        }.frame(minHeight: 44)
                        if club.ownerID == userID {
                            Button("Remove member", role: .destructive) { destructiveAction = .remove(member.id) }.font(.caption).frame(minHeight: 44)
                        }
                    }
                    Divider()
                }
            }
            Text("Companions stay a mystery. Your club sees friendly aliases, never pet names, species, or special moves.")
                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
        }.pawCard()
    }

    private func encouragement(_ club: RunningClub) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Little words of encouragement", systemImage: "heart").font(.headline)
            ForEach(club.cheers.prefix(10)) { cheer in
                VStack(alignment: .leading, spacing: 5) {
                    Label(cheer.kind.title, systemImage: cheer.kind.symbol).font(.subheadline.bold())
                    Text("\(club.members.first { $0.id == cheer.senderID }?.alias ?? "A friend") → \(club.members.first { $0.id == cheer.recipientID }?.alias ?? "A friend")")
                        .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                }
            }
        }.pawCard()
    }
}

private enum ClubDestructiveAction {
    case erase, leave, close, remove(String), cancel(String)
    var title: String { switch self { case .erase: "Remove your shared activity days?"; case .leave: "Leave this club?"; case .close: "Close this club for everyone?"; case .remove: "Remove this member?"; case .cancel: "Cancel this group activity?" } }
    var button: String { switch self { case .erase: "Remove shared days"; case .leave: "Leave club"; case .close: "Close club"; case .remove: "Remove member"; case .cancel: "Cancel activity" } }
    var detail: String {
        switch self {
        case .erase: "This turns sharing off and removes your contributions from this club. Buddy growth and your private workout history stay as they are."
        case .leave: "Your shared days and encouragement will be removed from this club. Your personal plans remain."
        case .close: "The club, shared progress, invitations and activities will be removed for every member. This cannot be undone."
        case .remove: "Their shared days and encouragement will be removed. The current invitation will also expire so they cannot rejoin with it."
        case .cancel: "Members will see that the group activity is cancelled. Copies they already saved in Planner remain their own plans."
        }
    }
}

struct ClubEventEditor: View {
    @ObservedObject var store: ClubStore
    let clubID: String
    @Environment(\.dismiss) private var dismiss
    @State private var activity: WorkoutActivity = .walking
    @State private var scheduledAt = Date().addingTimeInterval(86_400)
    @State private var duration = 20
    var body: some View {
        NavigationStack {
            Form {
                Picker("Activity", selection: $activity) {
                    ForEach(ClubEvent.supportedActivities) { Text($0.displayName).tag($0) }
                }
                DatePicker("When", selection: $scheduledAt, in: Date()...Date().addingTimeInterval(365 * 86_400))
                Stepper("\(duration) minutes", value: $duration, in: 5...240, step: 5)
                Text("Members choose whether to add this to their Planner. There’s no automatic attendance or workout credit.")
                Button("Schedule for the club") {
                    if store.enqueue(ClubCommand(action: "event", clubID: clubID, data: .init(activity: activity, scheduledAt: scheduledAt, durationMinutes: duration))) { dismiss() }
                }
                if let message = store.message { Text(message).font(.footnote) }
            }
            .navigationTitle("Plan together").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(PawTheme.adventureBlue)
    }
}
