import SwiftUI

struct PlannerView: View {
    @ObservedObject var planner: PlannerStore
    @ObservedObject var history: WorkoutHistoryStore
    @ObservedObject var petStore: PetStore
    var canStartWorkout = true
    var onStart: (PlannedActivity) async -> Void = { _ in }
    @State private var selectedDate = Date()
    @State private var editingPlan: PlannedActivity?
    @State private var deletingPlan: PlannedActivity?
    @State private var isStarting = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var weekStart: Date { CompanionJourney.weekStart(selectedDate) }
    private var dayPlans: [PlannedActivity] { planner.plans(on: selectedDate) }
    private var dayWorkouts: [RunSummary] {
        history.workouts.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: selectedDate) }
    }
    private var todayPlan: PlannedActivity? {
        planner.plans(on: .now).first { $0.completion == nil && !$0.isRestDay }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    weekPicker
                    todayCard
                    daySection
                    weeklyRhythm
                    if !dayWorkouts.isEmpty { completedWorkouts }
                    if let message = planner.storageMessage { messageCard(message) }
                    if let message = planner.reminderMessage { messageCard(message) }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(PawTheme.background.ignoresSafeArea())
            .navigationTitle("Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PawTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addPlan() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a plan")
                }
            }
            .sheet(item: $editingPlan) { plan in
                PlannerEditorView(plan: plan, planner: planner, history: history)
            }
            .confirmationDialog("Remove this plan?", isPresented: Binding(get: { deletingPlan != nil }, set: { if !$0 { deletingPlan = nil } }), titleVisibility: .visible) {
                Button("Remove plan", role: .destructive) {
                    if let plan = deletingPlan { _ = planner.remove(plan.id) }
                    deletingPlan = nil
                }
            } message: { Text("Your workouts and companion’s progress will stay safe.") }
            .onAppear { planner.reconcile(history.workouts); planner.refreshReminders() }
            .onChange(of: history.workouts) { _, workouts in planner.reconcile(workouts) }
        }
        .tint(PawTheme.adventureBlue)
        .foregroundStyle(PawTheme.ink)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                Text("Your week, at your pace.").font(.headline)
            } else {
                Text("A LITTLE TIME FOR YOU").font(.caption.weight(.bold)).tracking(1.8).foregroundStyle(PawTheme.adventureBlue)
                Text("Find your rhythm.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("A walk, a stretch, a quiet day. Make room for what feels right.")
                    .foregroundStyle(PawTheme.inkSecondary)
            }
        }
    }

    private var weekPicker: some View {
        VStack(spacing: 16) {
            HStack {
                Button { moveWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 44) }
                    .accessibilityLabel("Previous week")
                Spacer(minLength: 4)
                Text(weekStart, format: .dateTime.month(.wide).year()).font(.headline)
                Spacer(minLength: 4)
                Button { moveWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 44) }
                    .accessibilityLabel("Next week")
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { offset in
                            if let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart) {
                                dayButton(date).id(CompanionJourney.dayKey(date))
                            }
                        }
                    }
                    .frame(minWidth: typeSize.isAccessibilitySize ? 490 : 0)
                }
                .onAppear { proxy.scrollTo(CompanionJourney.dayKey(selectedDate), anchor: .center) }
                .onChange(of: selectedDate) { _, date in proxy.scrollTo(CompanionJourney.dayKey(date), anchor: .center) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { calendarLegend }
                VStack(alignment: .leading, spacing: 8) { calendarLegend }
            }
            .font(.caption2)
            .frame(maxWidth: .infinity)
            Button("Back to today") { selectedDate = .now }.font(.caption.weight(.semibold))
        }
        .pawCard(padding: 12)
    }

    @ViewBuilder private var calendarLegend: some View {
                Label("Planned", systemImage: "circle.fill").foregroundStyle(PawTheme.adventureBlue)
                Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(PawTheme.grassGreen)
                Label("Rest", systemImage: "moon.fill").foregroundStyle(PawTheme.inkSecondary)
    }

    private func dayButton(_ date: Date) -> some View {
        let plans = planner.plans(on: date)
        let hasWorkout = history.workouts.contains { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
        let hasCompleted = hasWorkout || plans.contains { $0.completion != nil }
        let hasPending = plans.contains { !$0.isRestDay && $0.completion == nil }
        let hasRest = plans.contains(where: \.isRestDay)
        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let status = [(hasCompleted ? "Completed activity" : nil), (hasPending ? "Activity planned" : nil), (hasRest ? "Rest day" : nil)].compactMap { $0 }.joined(separator: ", ")
        return Button { selectedDate = date } label: {
            VStack(spacing: 9) {
                Text(date, format: .dateTime.weekday(.narrow)).font(.caption)
                Text(date, format: .dateTime.day()).font(.system(.headline, design: .rounded))
                HStack(spacing: 2) {
                    if hasPending { Image(systemName: "circle.fill") }
                    if hasCompleted { Image(systemName: "checkmark.circle.fill") }
                    if hasRest { Image(systemName: "moon.fill") }
                    if status.isEmpty { Image(systemName: "circle.fill").opacity(0.15) }
                }.font(.system(size: 9))
            }
            .frame(width: typeSize.isAccessibilitySize ? 64 : 44)
            .frame(minHeight: typeSize.isAccessibilitySize ? 120 : 84)
            .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
            .foregroundStyle(selected ? PawTheme.buttonForeground : PawTheme.ink)
            .background(selected ? PawTheme.adventureBlue : Color.clear, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month().day())), \(status.isEmpty ? "No plans" : status)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("TODAY, TOGETHER", systemImage: "sun.max").font(.caption.weight(.bold)).tracking(1)
            if let plan = todayPlan {
                Text(plan.displayTitle).font(.system(.title2, design: .rounded, weight: .bold))
                Text("\(plan.scheduledAt.formatted(date: .omitted, time: .shortened)) · \(plan.durationMinutes) minutes")
                    .font(.subheadline)
                Text(companionConnection).font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                Button {
                    isStarting = true
                    Task { await onStart(plan); isStarting = false }
                } label: {
                    Label(isStarting ? "Getting ready…" : "Start \(plan.activity.displayName.lowercased())", systemImage: plan.activity.symbol)
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PawTheme.buttonForeground)
                .background(PawTheme.adventureBlue, in: Capsule())
                .disabled(!canStartWorkout || isStarting)
                if !canStartWorkout { Text("Finish or review your current workout before starting a new one.").font(.caption) }
            } else {
                let today = planner.plans(on: .now)
                Text(today.contains(where: \.isRestDay) ? "Room to recharge." : today.contains(where: { $0.completion != nil }) ? "A little promise, kept." : "What fits your day?")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(today.contains(where: \.isRestDay) ? "Your companion is happy to rest with you. Everything you’ve earned stays." : "Choose something gentle, or leave today open. Your journey is yours.")
                    .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                Button("Plan something for today") { addPlan(on: .now) }.font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 26))
    }

    private var companionConnection: String {
        let pet = petStore.snapshot
        if pet.lifeStage == .egg { return "Every credited minute brings your mystery egg a little closer to hello." }
        if pet.lifeStage == .baby { return "A little movement helps \(pet.name) grow. There’s no hurry." }
        if let trail = pet.journey.activeTrail { return "Your movement brings \(pet.name) closer to \(trail.title.lowercased())." }
        return "Exploring with \(pet.name) brings new memories and, eventually, another mystery egg."
    }

    private var daySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.title3.weight(.semibold))
            if dayPlans.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("A little open space", systemImage: "leaf").font(.headline)
                    Text("Add an activity or save this as a rest day.").font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                    Button("Add a plan") { addPlan() }.font(.subheadline.weight(.semibold))
                }.frame(maxWidth: .infinity, alignment: .leading).pawCard()
            }
            ForEach(dayPlans) { plan in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: plan.completion != nil ? "checkmark.circle.fill" : plan.isRestDay ? "moon.stars" : plan.activity.symbol)
                        .font(.title2).foregroundStyle(PawTheme.adventureBlue).frame(width: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(plan.displayTitle).font(.headline)
                        Text(plan.isRestDay ? "Rest day" : "\(plan.scheduledAt.formatted(date: .omitted, time: .shortened)) · \(plan.durationMinutes) min")
                            .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                        if let done = plan.completion {
                            Text("Completed · \(done.activeSeconds / 60) active min").font(.caption.weight(.semibold)).foregroundStyle(PawTheme.grassGreen)
                        } else if plan.reminderMinutesBefore != nil {
                            Label("Reminder requested", systemImage: "bell").font(.caption).foregroundStyle(PawTheme.inkSecondary)
                        }
                        if plan.completion == nil, !plan.isRestDay, plan.scheduledAt < Calendar.current.startOfDay(for: .now) {
                            Text("Move this to a day that suits you.").font(.caption).foregroundStyle(PawTheme.inkSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Menu {
                        if plan.completion == nil {
                            Button("Edit or reschedule", systemImage: "calendar") { editingPlan = plan }
                        }
                        Button("Remove plan", systemImage: "trash", role: .destructive) { deletingPlan = plan }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("Options for \(plan.displayTitle)")
                }.pawCard()
            }
        }
    }

    private var weeklyRhythm: some View {
        let journey = petStore.snapshot.journey
        let target = journey.target(inWeekOf: selectedDate)
        let days = journey.activeDays(inWeekOf: selectedDate)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Your weekly rhythm", systemImage: "sparkles").font(.headline)
            Text("\(days) of \(target) movement days").font(.title3.weight(.semibold))
            ProgressView(value: Double(min(days, target)), total: Double(target)).tint(PawTheme.adventureBlue)
            Text("Five progress minutes makes a movement day. Rest never takes away your keepsakes.")
                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            Text("Change your weekly rhythm in Buddy → Adventures.").font(.caption).foregroundStyle(PawTheme.inkSecondary)
        }.pawCard()
    }

    private var completedWorkouts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your movement that day").font(.title3.weight(.semibold))
            ForEach(dayWorkouts) { workout in
                NavigationLink { WorkoutDetailView(summary: workout) } label: {
                    HStack {
                        Image(systemName: workout.workoutConfiguration.activity.symbol).font(.title2).frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.workoutConfiguration.displayName).font(.headline)
                            Text("\(workout.elapsedSeconds / 60) active min · \(workout.startedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.pawCard()
                }.buttonStyle(.plain)
            }
        }
    }

    private func messageCard(_ message: String) -> some View {
        Label(message, systemImage: "info.circle").font(.footnote).foregroundStyle(PawTheme.inkSecondary).pawCard()
    }

    private func moveWeek(_ amount: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: amount * 7, to: selectedDate) ?? selectedDate
    }

    private func addPlan(on date: Date? = nil) {
        let date = date ?? selectedDate
        let time = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        editingPlan = PlannedActivity(scheduledAt: time)
    }
}

struct PlannerEditorView: View {
    @State var plan: PlannedActivity
    @ObservedObject var planner: PlannerStore
    @ObservedObject var history: WorkoutHistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosesActivity = false
    @State private var isSaving = false
    @State private var reminderDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Make room for", selection: $plan.isRestDay) {
                        Text("Movement").tag(false)
                        Text("Rest").tag(true)
                    }.pickerStyle(.segmented)
                    TextField("A name for your plan (optional)", text: $plan.title)
                        .onChange(of: plan.title) { _, title in plan.title = String(title.prefix(80)) }
                    if !plan.isRestDay {
                        Button { choosesActivity = true } label: {
                            HStack(spacing: 8) {
                                Text("Activity")
                                Spacer()
                                Image(systemName: plan.activity.symbol).font(.body)
                                Text(plan.activity.displayName).foregroundStyle(PawTheme.ink)
                                Image(systemName: "chevron.right").font(.caption)
                            }
                        }
                        Stepper("\(plan.durationMinutes) minutes", value: $plan.durationMinutes, in: 5...240, step: 5)
                    }
                    DatePicker(plan.isRestDay ? "Day" : "When", selection: $plan.scheduledAt,
                               displayedComponents: plan.isRestDay ? [.date] : [.date, .hourAndMinute])
                } header: { Text("Your plan") } footer: {
                    Text(plan.isRestDay ? "Rest days keep every bit of progress you’ve earned." : "A saved workout of this activity, on this day, that meets your planned minutes completes the plan. Each workout completes one plan.")
                }
                Section {
                    Toggle("Remind me", isOn: Binding(get: { plan.reminderMinutesBefore != nil }, set: { plan.reminderMinutesBefore = $0 ? 10 : nil }))
                    if plan.reminderMinutesBefore != nil {
                        if plan.isRestDay { DatePicker("Reminder time", selection: $plan.scheduledAt, displayedComponents: .hourAndMinute) }
                        Picker("Reminder", selection: Binding(get: { plan.reminderMinutesBefore ?? 10 }, set: { plan.reminderMinutesBefore = $0 })) {
                            Text("At the start").tag(0)
                            Text("10 minutes before").tag(10)
                            Text("30 minutes before").tag(30)
                            Text("1 hour before").tag(60)
                        }
                        if (plan.reminderDate ?? .distantPast) <= .now { Text("Choose a future time to receive a reminder.").font(.caption).foregroundStyle(PawTheme.inkSecondary) }
                    }
                } footer: { Text("Reminders are optional. The lock screen won’t show your activity details.") }
                if let message = planner.storageMessage { Text(message).font(.footnote).foregroundStyle(PawTheme.coralOrange) }
            }
            .scrollContentBackground(.hidden)
            .background(PawTheme.background)
            .navigationTitle(planner.plans.contains(where: { $0.id == plan.id }) ? "Edit your plan" : "A little plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }.disabled(isSaving || !plan.isValid)
                }
            }
            .sheet(isPresented: $choosesActivity) {
                WorkoutPickerView(selection: plan.activity) { plan.activity = $0 }
            }
            .alert("Plan saved, reminders are off", isPresented: $reminderDenied) {
                Button("OK") { dismiss() }
            } message: { Text("You can allow notifications for PawPace in iPhone Settings. Your plan is saved either way.") }
            .interactiveDismissDisabled(isSaving)
        }.tint(PawTheme.adventureBlue)
    }

    private func save() {
        isSaving = true
        Task {
            var allowed = true
            if plan.reminderDate.map({ $0 > .now }) ?? false { allowed = await planner.reminders.requestPermission() }
            let saved = planner.save(plan, workouts: history.workouts)
            isSaving = false
            if saved {
                if allowed { dismiss() } else { reminderDenied = true }
            }
        }
    }
}
