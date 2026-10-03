import SwiftUI

struct FriendsFeedView: View {
    @ObservedObject var store: ClubStore
    var history: WorkoutHistoryStore?
    private var pendingRemovalIDs: Set<String> {
        Set(store.pending.filter { ["friendRemove", "friendBlock"].contains($0.command.action) }.compactMap { $0.command.data.memberID })
    }
    private var posts: [FriendPost] {
        let deleted = Set(store.pending.filter { $0.command.action == "friendDeletePost" }.compactMap { $0.command.data.postID })
        return (store.social?.posts ?? []).filter { !deleted.contains($0.id) && !pendingRemovalIDs.contains($0.authorID) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                count("\(store.friends.filter { !pendingRemovalIDs.contains($0.id) }.count)", label: "friends", symbol: "person.2.fill")
                let week = posts.filter { $0.endedAt >= CompanionJourney.weekStart(.now) }
                count("\(week.count)", label: "shared this week", symbol: "figure.run")
            }.pawCard()
            HStack {
                Text("Little victories").font(.title2.bold())
                Spacer()
                if let history, store.session != nil {
                    NavigationLink { FriendWorkoutPicker(store: store, history: history) } label: {
                        Image(systemName: "square.and.pencil").font(.title3).frame(width: 44, height: 44)
                    }.accessibilityLabel("Share a saved workout with friends")
                }
            }
            if posts.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "sun.max").font(.system(size: 36)).foregroundStyle(PawTheme.adventureBlue)
                    Text("Every little effort belongs here").font(.title3.bold())
                    Text("A morning run, a slow walk, a moment to stretch. Add friends, then share the workouts you want to celebrate together.")
                        .foregroundStyle(PawTheme.inkSecondary)
                }.pawCard()
            }
            ForEach(posts) { post in FriendPostCard(store: store, post: post) }
            if let date = store.archive?.snapshot?.fetchedAt {
                Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }
            Text("Only accepted friends see new posts. This feed shows the latest 100 shared workouts from the last 30 days. Sharing is always your choice.")
                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
        }
    }
    private func count(_ value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(PawTheme.adventureBlue)
            Text(value).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(label).font(.caption).foregroundStyle(PawTheme.inkSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FriendPostCard: View {
    @ObservedObject var store: ClubStore
    let post: FriendPost
    @State private var deleting = false
    private var mine: Bool { post.authorID == store.session?.account.id }
    private var cheering: Bool { post.cheeredByMe || store.pending.contains { $0.command.action == "friendCheer" && $0.command.data.postID == post.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill").font(.title3).foregroundStyle(PawTheme.adventureBlue)
                    .frame(width: 44, height: 44).background(PawTheme.surfaceRaised, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(mine ? "You · \(post.alias)" : post.alias).font(.headline)
                    Text(post.endedAt, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(PawTheme.inkSecondary)
                }
                Spacer(minLength: 0)
                if mine {
                    Button("Remove post", systemImage: "ellipsis") { deleting = true }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
            }
            Label(post.activity.displayName, systemImage: post.activity.symbol).font(.title3.bold())
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { metrics }
                VStack(alignment: .leading, spacing: 14) { metrics }
            }
            Divider()
            HStack {
                Label("\(post.cheerCount) cheers", systemImage: "hands.clap").font(.caption).foregroundStyle(PawTheme.inkSecondary)
                Spacer()
                if !mine {
                    Button(cheering ? "Cheered!" : "Cheer them on", systemImage: cheering ? "heart.fill" : "heart") {
                        _ = store.enqueue(ClubCommand(action: "friendCheer", data: .init(postID: post.id)))
                    }.font(.subheadline.bold()).disabled(cheering).frame(minHeight: 44)
                }
            }
        }.pawCard()
        .confirmationDialog("Remove this shared workout?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Remove post", role: .destructive) {
                _ = store.enqueue(ClubCommand(action: "friendDeletePost", data: .init(postID: post.id)))
            }
        } message: { Text("Your private workout journal will keep its original entry.") }
    }
    @ViewBuilder private var metrics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PawPaceFormatting.duration(seconds: post.elapsedSeconds)).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
            Text("active time").font(.caption).foregroundStyle(PawTheme.inkSecondary)
        }
        if let distance = post.distanceMeters {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(PawPaceFormatting.distance(kilometers: distance / 1_000)) km").font(.system(.title2, design: .rounded, weight: .bold))
                Text("distance").font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }
        }
    }
}

struct FriendsListView: View {
    @ObservedObject var store: ClubStore
    @State private var code = ""
    @State private var chosen: FriendConnection?
    @State private var codeMessage: String?
    @State private var rotating = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Your kind of company").font(.title2.bold())
            Text("Invite people you know. You both choose to connect before any workouts are shared.")
                .foregroundStyle(PawTheme.inkSecondary)
            if let social = store.social {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your private friend code").font(.headline)
                    Text(social.friendCode).font(.system(.subheadline, design: .monospaced, weight: .semibold)).textSelection(.enabled)
                    ShareLink(item: social.friendCode) { Label("Share code", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                    Button("Replace code") { rotating = true }.font(.caption).frame(minHeight: 44)
                }.pawCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add a friend").font(.headline)
                    TextField("Paste their friend code", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Friend code")
                    Button("Send friend request", systemImage: "person.badge.plus") {
                        let value = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        guard value.count == 16, value.allSatisfy(\.isHexDigit) else { codeMessage = "Enter the 16-character code your friend shared."; return }
                        if store.enqueue(ClubCommand(action: "friendRequest", data: .init(token: value))) {
                            code = ""; codeMessage = "Request queued. It will appear after syncing."
                        }
                    }.buttonStyle(.borderedProminent).foregroundStyle(PawTheme.buttonForeground)
                    if let codeMessage { Text(codeMessage).font(.caption) }
                }.pawCard()
                let removed = Set(store.pending.filter { ["friendRemove", "friendBlock"].contains($0.command.action) }.compactMap { $0.command.data.memberID })
                ForEach(social.connections.filter { !removed.contains($0.id) }) { friend in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(friend.alias, systemImage: "person.crop.circle").font(.headline)
                            Spacer()
                            Button("Manage friend", systemImage: "ellipsis") { chosen = friend }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                        }
                        if friend.status == .incoming {
                            Text("Would like to be your friend").font(.caption).foregroundStyle(PawTheme.inkSecondary)
                            Button("Accept request") { _ = store.enqueue(ClubCommand(action: "friendAccept", data: .init(memberID: friend.id))) }
                                .buttonStyle(.borderedProminent).foregroundStyle(PawTheme.buttonForeground)
                                .disabled(store.pending.contains { $0.command.action == "friendAccept" && $0.command.data.memberID == friend.id })
                        } else if friend.status == .outgoing {
                            Text("Waiting for them to accept").font(.caption).foregroundStyle(PawTheme.inkSecondary)
                        } else {
                            let posts = social.posts.filter { $0.authorID == friend.id }
                            Text(posts.isEmpty ? "Their next shared adventure will appear in your feed." : "\(posts.count) recent shared workout\(posts.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                            if let last = posts.first {
                                Label("\(last.activity.displayName) · \(PawPaceFormatting.duration(seconds: last.elapsedSeconds))", systemImage: last.activity.symbol).font(.subheadline)
                            }
                        }
                    }.pawCard()
                }
                if !social.blocks.isEmpty {
                    DisclosureGroup("Blocked accounts") {
                        ForEach(social.blocks) { blocked in
                            HStack {
                                Text(blocked.alias); Spacer()
                                Button("Unblock") { _ = store.enqueue(ClubCommand(action: "friendUnblock", data: .init(memberID: blocked.id))) }
                            }.font(.subheadline).frame(minHeight: 44)
                        }
                    }
                }
            } else {
                Label(store.session == nil ? "Connect your account to invite your first friend." : "Sync to load your friends and private code.", systemImage: "person.2.badge.plus")
                    .foregroundStyle(PawTheme.inkSecondary).pawCard()
            }
        }
        .confirmationDialog("Manage \(chosen?.alias ?? "friend")", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible) {
            if let friend = chosen {
                Button(friend.status == .accepted ? "Remove friend" : "Dismiss request", role: .destructive) { store.removeFriend(friend.id, block: false) }
                Button("Block account", role: .destructive) { store.removeFriend(friend.id, block: true) }
            }
        } message: { Text("Removing or blocking stops access to each other’s posts. Unblocking doesn’t restore the friendship.") }
        .confirmationDialog("Replace your friend code?", isPresented: $rotating, titleVisibility: .visible) {
            Button("Replace code") { _ = store.enqueue(ClubCommand(action: "friendCode")) }
        } message: { Text("The old code will stop working after syncing. Existing friends stay connected.") }
    }
}

struct FriendWorkoutPicker: View {
    @ObservedObject var store: ClubStore
    @ObservedObject var history: WorkoutHistoryStore
    var body: some View {
        List {
            Section {
                ForEach(history.workouts.filter { $0.endedAt > Date().addingTimeInterval(-30 * 86_400) && $0.elapsedSeconds > 0 }) { workout in
                    NavigationLink {
                        FriendPostComposer(store: store, summary: workout)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(workout.workoutConfiguration.displayName, systemImage: workout.workoutConfiguration.activity.symbol).font(.headline)
                            Text("\(workout.endedAt.formatted(date: .abbreviated, time: .omitted)) · \(PawPaceFormatting.duration(seconds: workout.elapsedSeconds))")
                                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                        }
                    }
                }
            } footer: { Text("Choose a saved workout from the last 30 days. You’ll see exactly what will be shared before posting.") }
        }.navigationTitle("Share a little victory").navigationBarTitleDisplayMode(.inline)
    }
}

struct FriendPostComposer: View {
    @ObservedObject var store: ClubStore
    let summary: RunSummary
    @State private var includeDistance = false
    @State private var queued = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label("A little victory, shared", systemImage: "sun.max").font(.title2.bold())
                Text("Your accepted friends can see this workout. New friends only see posts shared after you connect.").foregroundStyle(PawTheme.inkSecondary)
                VStack(alignment: .leading, spacing: 14) {
                    Text(store.session?.account.alias ?? "Your friendly alias").font(.headline)
                    Label(summary.workoutConfiguration.activity.displayName, systemImage: summary.workoutConfiguration.activity.symbol).font(.title3.bold())
                    Text(summary.endedAt, format: .dateTime.month(.abbreviated).day())
                    Text("\(PawPaceFormatting.duration(seconds: summary.elapsedSeconds)) active time").font(.headline)
                    if includeDistance { Text("\(PawPaceFormatting.distance(kilometers: summary.distanceKilometers)) km") }
                }.pawCard()
                if summary.workoutConfiguration.activity.supportsDistance { Toggle("Include distance", isOn: $includeDistance).disabled(queued) }
                Text("Only your alias, activity, workout date, active time and optional distance are posted. Your route, heart rate, calories and buddy stay private.")
                    .font(.footnote).foregroundStyle(PawTheme.inkSecondary)
                if let failed = store.pending.first(where: { $0.command.action == "friendPost" && $0.command.data.workoutID == summary.id.uuidString && $0.failure != nil }) {
                    Label(failed.failure ?? "This workout couldn’t be shared.", systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                    Button("Discard this post") { store.discard(failed.id); queued = false }
                        .buttonStyle(.bordered)
                } else if queued || store.isWorkoutSharedOrQueued(summary.id) {
                    Label("Shared or queued for your friends", systemImage: "checkmark.circle.fill").foregroundStyle(PawTheme.adventureBlue)
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent).foregroundStyle(PawTheme.buttonForeground)
                } else if store.session == nil || !store.isConfigured {
                    Text("Connect your account in Club to share with friends.").font(.subheadline)
                } else {
                    Button("Share with friends", systemImage: "person.2") {
                        queued = store.enqueue(.share(summary, includeDistance: includeDistance))
                    }.buttonStyle(.borderedProminent).foregroundStyle(PawTheme.buttonForeground).disabled(summary.elapsedSeconds <= 0)
                }
                if let message = store.message { Text(message).font(.caption).foregroundStyle(PawTheme.inkSecondary) }
            }.padding(24)
        }.background(PawTheme.background).foregroundStyle(PawTheme.ink)
            .navigationTitle("Share workout").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PawTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
