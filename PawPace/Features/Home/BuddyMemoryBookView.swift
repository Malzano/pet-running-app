import SwiftUI
import PhotosUI

struct BuddyMemoryBookView: View {
    @ObservedObject var store: PetStore
    @State private var selectedCompanion: UUID?
    private var friends: [CompanionResident] {
        ([CompanionResident(store.snapshot)] + store.snapshot.journey.residents).filter { $0.stage != .egg }
    }
    private var memories: [BuddyMemory] {
        store.snapshot.buddyMemories.filter { selectedCompanion == nil || $0.companionID == selectedCompanion }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Little moments, kept close")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("Your hatch days, first outings, new tricks and paths you’ve shared.")
                    .foregroundStyle(PawTheme.inkSecondary)
                if friends.count > 1 {
                    Picker("Companion", selection: $selectedCompanion) {
                        Text("Everyone at home").tag(nil as UUID?)
                        ForEach(friends) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.menu)
                }
                if memories.isEmpty {
                    ContentUnavailableView("Memories will grow here", systemImage: "book.closed",
                        description: Text("Keep exploring together. We only show moments with a saved date, so older milestones may not appear."))
                }
                ForEach(memories) { memory in
                    NavigationLink {
                        BuddyMemoryDetailView(memory: memory)
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: memory.symbol)
                                .font(.title2).foregroundStyle(PawTheme.adventureBlue).frame(width: 32)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(memory.title).font(.headline)
                                Text(memory.companionName).font(.subheadline)
                                Text(memory.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).pawCard()
                    }
                    .buttonStyle(.plain)
                }
                Text("Only friends you’ve met appear here. Older adventures stay in Everyone at home. Photos are optional and stay on this device; they aren’t backed up or sent to your club.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }.padding(22)
        }
        .background(PawTheme.background)
        .foregroundStyle(PawTheme.ink)
        .navigationTitle("Memory book")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PawTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct BuddyMemoryDetailView: View {
    let memory: BuddyMemory
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photo: Data?
    @State private var message: String?
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: memory.symbol).font(.system(size: 44)).foregroundStyle(PawTheme.adventureBlue)
                Text(memory.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("With \(memory.companionName) · \(memory.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                Text(memory.detail).font(.body)
                if let photo, let uiImage = UIImage(data: photo) {
                    Image(uiImage: uiImage).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 24))
                        .accessibilityLabel("Your photo for \(memory.title)")
                }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(photo == nil ? "Add a photo" : "Change photo", systemImage: "photo.badge.plus")
                        .frame(minHeight: 44)
                }.buttonStyle(.bordered).disabled(loading)
                if photo != nil {
                    Button("Remove photo", role: .destructive) {
                        do { try MemoryPhotoStore().remove(memoryID: memory.id); photo = nil; message = nil }
                        catch { message = error.localizedDescription }
                    }.frame(minHeight: 44).disabled(loading)
                }
                if loading { ProgressView("Saving photo…") }
                if let message { Text(message).font(.footnote).foregroundStyle(PawTheme.inkSecondary) }
                Text("Saved only on this device, without photo location metadata. Removing it here doesn’t change your photo library.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }.padding(22)
        }
        .background(PawTheme.background).foregroundStyle(PawTheme.ink)
        .navigationTitle("A little memory").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PawTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            do { photo = try MemoryPhotoStore().load(memoryID: memory.id) }
            catch { message = error.localizedDescription }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            loading = true
            defer { loading = false; self.selectedPhoto = nil }
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else { throw MemoryPhotoStore.PhotoError.invalidImage }
                try Task.checkCancellation()
                photo = try MemoryPhotoStore().save(data, memoryID: memory.id)
                message = nil
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
}
