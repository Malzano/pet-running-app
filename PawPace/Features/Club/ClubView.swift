import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct ClubView: View {
    @ObservedObject var store: ClubStore
    @ObservedObject var planner: PlannerStore
    @ObservedObject var petStore: PetStore
    var history: WorkoutHistoryStore? = nil
    @State private var section = 0
    @State private var sheet: ClubSheet?
    @State private var nonce = ""
    @State private var signInError: String?

    init(store: ClubStore, planner: PlannerStore, petStore: PetStore, history: WorkoutHistoryStore? = nil, initialSection: Int = 0) {
        self.store = store; self.planner = planner; self.petStore = petStore; self.history = history
        _section = State(initialValue: min(2, max(0, initialSection)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Our little circle")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Little victories feel even better with friends.")
                        .foregroundStyle(PawTheme.inkSecondary)
                    Picker("Community", selection: $section) {
                        Text("Feed").tag(0)
                        Text("Friends").tag(1)
                        Text("Clubs").tag(2)
                    }.pickerStyle(.segmented)
                    if section == 0 { FriendsFeedView(store: store, history: history) }
                    else if section == 1 { FriendsListView(store: store) }
                    else if store.session == nil { welcome }
                    else { clubs }
                    if store.session == nil, section != 2 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.isConfigured ? "A place for your people" : "Friends aren’t connected in this build yet")
                                .font(.headline)
                            Text(store.isConfigured ? "Connect your account to add friends and share your adventures." : "Your private feed will appear when the account service is connected. Daily adventures and your buddy are ready now.")
                                .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                            if store.isConfigured { Button("Connect account") { sheet = .connect }.buttonStyle(.borderedProminent).foregroundStyle(PawTheme.buttonForeground) }
                        }.pawCard()
                    }
                    if store.isSyncing { ProgressView("Connecting with your club…") }
                    if let message = signInError ?? store.message {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message).font(.footnote)
                            if store.session != nil { Button("Try syncing again") { Task { await store.refresh() } }.frame(minHeight: 44) }
                        }.pawCard()
                    }
                    if !store.pending.isEmpty { pending }
                }.padding(22)
            }
            .background(PawTheme.background).foregroundStyle(PawTheme.ink)
            .navigationTitle("Club").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PawTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if store.session != nil {
                    ToolbarItem(placement: .topBarTrailing) { Button("Account", systemImage: "person.crop.circle") { sheet = .account } }
                }
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
            .sheet(item: $sheet) { item in
                switch item {
                case .connect:
                    NavigationStack { ScrollView { welcome.padding(22) }.navigationTitle("Connect with friends") }
                case .create: ClubCreateView(store: store)
                case .join: ClubJoinView(store: store, initialText: store.incomingInvitation ?? "")
                case .account: ClubAccountView(store: store)
                case .invitation:
                    if let invitation = store.invitation { ClubInvitationView(invitation: invitation) }
                }
            }
            .onChange(of: store.invitation?.id) { _, value in if value != nil { sheet = .invitation } }
            .onChange(of: store.incomingInvitation) { _, value in if value != nil, store.session != nil { sheet = .join } }
            .onChange(of: store.session?.account.id) { _, value in
                if value == nil { sheet = nil }
                else if store.incomingInvitation != nil { sheet = .join }
                else if sheet == .connect { sheet = nil }
            }
        }.tint(PawTheme.adventureBlue)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            ClubCampsiteView(level: 0)
            Text("Make a home for your club").font(.title2.bold())
            Label("Private invitations for your friends", systemImage: "envelope")
            Label("A shared weekly goal, at everyone’s pace", systemImage: "leaf")
            Label("Group activities that fit your planner", systemImage: "calendar")
            Text("Sign in to create or join a club. We give you a friendly alias; your Apple name and email aren’t requested. Sharing activity days and workout results is always your choice. Your Buddy and Planner work without an account.")
                .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
            if store.isConfigured {
                SignInWithAppleButton(.continue) { request in
                    var bytes = [UInt8](repeating: 0, count: 32)
                    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                        signInError = "Sign-in couldn’t start securely. Please try again."; nonce = ""; return
                    }
                    nonce = Data(bytes).base64EncodedString()
                    request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
                    request.requestedScopes = []
                } onCompletion: { result in
                    switch result {
                    case let .success(authorization):
                        guard !nonce.isEmpty, let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                              let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                              let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) else {
                            signInError = "Apple didn’t return a complete sign-in. Please try again."; return
                        }
                        let usedNonce = nonce; nonce = ""; signInError = nil
                        Task { await store.signIn(identityToken: token, nonce: usedNonce, authorizationCode: code) }
                    case let .failure(error):
                        nonce = ""
                        if (error as? ASAuthorizationError)?.code != .canceled { signInError = "Sign-in didn’t finish. Please try again." }
                    }
                }
                .signInWithAppleButtonStyle(.black).frame(height: 52).disabled(store.isSyncing)
            } else {
                Label("Club isn’t connected in this build yet. Buddy and Planner are ready to use.", systemImage: "icloud.slash")
                    .font(.subheadline).foregroundStyle(PawTheme.inkSecondary).pawCard()
            }
            if store.incomingInvitation != nil { Text("Your invitation is ready. Sign in to review it.").font(.footnote) }
        }
    }

    private var clubs: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let account = store.session?.account { Text("Here as \(account.alias)").font(.subheadline).foregroundStyle(PawTheme.inkSecondary) }
            ViewThatFits(in: .horizontal) {
                HStack { createButton; joinButton }
                VStack(alignment: .leading) { createButton; joinButton }
            }
            if store.clubs.isEmpty {
                ClubCampsiteView(level: 0)
                Text("There’s room for your people here").font(.title2.bold())
                Text("Start a private club or join with a friend’s invitation. Members and progress will appear after your club connects.")
                    .foregroundStyle(PawTheme.inkSecondary)
            }
            ForEach(store.clubs) { club in
                NavigationLink {
                    ClubDetailView(store: store, planner: planner, petStore: petStore, clubID: club.id)
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(ClubPrivacy.title(club.name, pet: petStore.snapshot)).font(.title3.bold())
                            Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }
                        Text("\(club.members.count) \(club.members.count == 1 ? "member" : "members") · \(club.weeklyDays) / \(club.weeklyTarget) activity days this week")
                            .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                        ProgressView(value: Double(min(club.weeklyDays, club.weeklyTarget)), total: Double(club.weeklyTarget))
                        Text(club.campTitle).font(.caption)
                    }.pawCard()
                }.buttonStyle(.plain)
            }
            if let fetched = store.archive?.snapshot?.fetchedAt {
                Text("Last synced \(fetched.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }
        }
    }
    private var createButton: some View {
        Button("Create a club", systemImage: "plus") { sheet = .create }
            .buttonStyle(.borderedProminent).foregroundStyle(PawTheme.buttonForeground)
    }
    private var joinButton: some View { Button("Join a club", systemImage: "envelope.open") { sheet = .join }.buttonStyle(.bordered) }
    private var pending: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath").font(.headline)
            Text("Queued requests, posts and club actions reach your friends after syncing.").font(.caption).foregroundStyle(PawTheme.inkSecondary)
            ForEach(store.pending) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.command.description).font(.subheadline.bold())
                    if let failure = item.failure {
                        Text(failure).font(.caption)
                        HStack {
                            Button("Retry") { store.retry(item.id) }
                            Button("Discard", role: .destructive) { store.discard(item.id) }
                        }.buttonStyle(.bordered)
                    }
                }
            }
        }.pawCard()
    }
    private enum ClubSheet: String, Identifiable { case create, join, account, invitation, connect; var id: String { rawValue } }
}

struct ClubCampsiteView: View {
    let level: Int
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28).fill(PawTheme.habitatGradient)
            Ellipse().fill(PawTheme.grassGreen.opacity(0.23)).frame(width: 250, height: 65).offset(y: 65)
            HStack(alignment: .bottom, spacing: 28) {
                Image(systemName: "tree.fill").font(.system(size: 62)).foregroundStyle(PawTheme.grassGreen)
                Image(systemName: level >= 2 ? "tent.fill" : "leaf.circle.fill")
                    .font(.system(size: 82)).foregroundStyle(PawTheme.adventureBlue)
                Image(systemName: level >= 1 ? "camera.macro" : "tree.fill")
                    .font(.system(size: 44)).foregroundStyle(level >= 1 ? PawTheme.coralOrange : PawTheme.grassGreen)
            }.offset(y: 18)
            if level >= 3 {
                Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(PawTheme.coralOrange).offset(x: 65, y: -65)
            }
            Image(systemName: "cloud.fill").font(.system(size: 38)).foregroundStyle(.white.opacity(0.9)).offset(x: -90, y: -65)
        }
        .frame(height: 220).accessibilityElement(children: .ignore)
        .accessibilityLabel(["A quiet clearing ready for friends", "Flowers growing at the campsite", "A tent for your club to gather around", "Your campsite glowing with shared memories"][min(3, max(0, level))])
    }
}

struct ClubCreateView: View {
    @ObservedObject var store: ClubStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var target = 7
    var body: some View {
        NavigationStack {
            Form {
                Section("Your gathering place") { TextField("Club name", text: $name).textInputAutocapitalization(.words) }
                Section("A gentle shared goal") {
                    Stepper("\(target) activity days a week", value: $target, in: 2...70)
                    Text("One friend moving on one day counts as one activity day. Five credited minutes is enough. Everyone chooses whether to share.")
                    Text("Club weeks begin Monday in \(TimeZone.current.identifier).")
                }
                Section {
                    Text("You’ll host this private club and control invitations and group activities. Companions, photos, routes and Health measurements stay private.")
                    Button("Create club") {
                        if store.enqueue(ClubCommand(action: "create", data: .init(name: name.trimmingCharacters(in: .whitespacesAndNewlines), timeZone: TimeZone.current.identifier, weeklyTarget: target))) { dismiss() }
                    }.disabled(!(2...40).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count))
                }
                if let message = store.message { Text(message).font(.footnote) }
            }
            .navigationTitle("Create a club").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(PawTheme.adventureBlue)
    }
}

struct ClubJoinView: View {
    @ObservedObject var store: ClubStore
    @Environment(\.dismiss) private var dismiss
    @State private var invitation: String
    init(store: ClubStore, initialText: String = "") { self.store = store; _invitation = State(initialValue: initialText) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Your private invitation") {
                    TextField("Paste invitation link", text: $invitation, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Text("Invitations last seven days and can be replaced by the host. Only share one with people you want in your club.")
                }
                Section {
                    Text("Other members will see your Club alias. Activity-day sharing starts off. Your companion’s identity, names and special moves stay private.")
                    Button("Join club") {
                        guard let token = ClubStore.invitationToken(invitation) else { return }
                        if store.enqueue(ClubCommand(action: "join", data: .init(token: token))) { store.incomingInvitation = nil; dismiss() }
                    }.disabled(ClubStore.invitationToken(invitation) == nil)
                }
                if let message = store.message { Text(message).font(.footnote) }
            }
            .navigationTitle("Join a club").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(PawTheme.adventureBlue)
    }
}

struct ClubInvitationView: View {
    let invitation: ClubStore.Invitation
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Label("A place for your friends", systemImage: "envelope.open").font(.title2.bold())
                Text("Anyone you give this private link can join with their Club account. Creating another invitation replaces this one.")
                Text("Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))").font(.subheadline)
                ShareLink("Share private invitation", item: invitation.url).buttonStyle(.borderedProminent).foregroundStyle(PawTheme.buttonForeground)
                Text(invitation.url.absoluteString).font(.caption).textSelection(.enabled).privacySensitive()
                Spacer()
            }.padding(22).background(PawTheme.background)
                .navigationTitle("Invite friends").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(PawTheme.adventureBlue)
    }
}

struct ClubAccountView: View {
    @ObservedObject var store: ClubStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false
    @State private var confirmsSignOut = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Your Club account") {
                    Text(store.session?.account.alias ?? "Signed out")
                    Text("Your alias is separate from your companion. Clubs receive activity days only after opt-in. Friends see only the workout results you explicitly post: activity, date, active time and optional distance. Routes, heart rate, photos and companion identities stay private.")
                }
                Section {
                    Button("Sign out") { confirmsSignOut = true }.disabled(store.isSyncing)
                    Button("Delete Club account", role: .destructive) { confirmsDelete = true }.disabled(store.isSyncing)
                    Text("Buddy, local memories and Planner remain on this phone.")
                }
                if let message = store.message { Text(message).font(.footnote) }
            }
            .navigationTitle("Club account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Sign out of Club?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await store.signOut(); if store.session == nil { dismiss() } } }
            } message: { Text("This removes the saved Club view and unsent actions from this phone. Your shared clubs remain.") }
            .confirmationDialog("Delete your Club account?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { Task { await store.deleteAccount(); if store.session == nil { dismiss() } } }
            } message: { Text("Your friendships, posts, memberships, shared activity and encouragement will be removed. Clubs you host will close for everyone. This cannot be undone.") }
        }.tint(PawTheme.adventureBlue)
    }
}
