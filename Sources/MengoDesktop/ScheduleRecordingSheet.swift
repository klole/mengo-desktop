import SwiftUI

/// Modal sheet for managing the user's `RecordingSchedule`. Reads + writes
/// `SettingsStore.recordingSchedule`; the recorder enforces the schedule
/// automatically on its health-poll tick.
///
/// Layout: a list of existing rules with delete affordances, an "Add
/// recurring" + "Add one-off" pair of forms below. The active recording
/// state isn't touched from this sheet — the recorder picks up changes on
/// the next tick.
struct ScheduleRecordingSheet: View {
    let settings: SettingsStore
    var onClose: () -> Void = {}

    @State private var newDays: Set<Weekday> = []
    @State private var newStart = Date()
    @State private var newEnd = Date(timeIntervalSinceNow: 3600)
    @State private var oneOffStart = Date()
    @State private var oneOffEnd = Date(timeIntervalSinceNow: 3600)

    private var rules: [RecordingScheduleRule] { settings.recordingSchedule?.rules ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            ScrollView { content.padding(20) }
        }
        .background(Theme.paneBackground)
        .frame(minWidth: 560, minHeight: 540)
    }

    @ViewBuilder private var header: some View {
        HStack {
            Text("Schedule Recording").font(Theme.title).foregroundStyle(Theme.primaryText)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(Theme.cardBackground)
                            .overlay(Circle().stroke(Theme.separator, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            if rules.isEmpty {
                emptyRules
            } else {
                existingRules
            }
            addRecurringForm
            addOneOffForm
        }
    }

    @ViewBuilder private var emptyRules: some View {
        Text("No schedule set. Without a schedule, the recorder runs whenever you ask it to. Add a rule below to auto-pause/resume on a calendar.")
            .font(Theme.body).foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var existingRules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active rules").font(Theme.headline).foregroundStyle(Theme.primaryText)
            ForEach(rules) { rule in
                ruleRow(rule)
            }
        }
    }

    private func ruleRow(_ rule: RecordingScheduleRule) -> some View {
        HStack {
            Image(systemName: rule.isRecurring ? "repeat" : "calendar")
                .foregroundStyle(Theme.accent)
            Text(rule.summary).font(Theme.body).foregroundStyle(Theme.primaryText)
            Spacer()
            Button {
                removeRule(rule.id)
            } label: {
                Image(systemName: "trash").foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, lineWidth: 1))
        )
    }

    @ViewBuilder private var addRecurringForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add recurring rule").font(Theme.headline).foregroundStyle(Theme.primaryText)
            HStack(spacing: 6) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Button {
                        if newDays.contains(day) { newDays.remove(day) } else { newDays.insert(day) }
                    } label: {
                        Text(day.shortName)
                            .font(Theme.caption)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(newDays.contains(day) ? .white : Theme.primaryText)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(newDays.contains(day) ? Theme.accent : Theme.cardBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                DatePicker("Start", selection: $newStart, displayedComponents: .hourAndMinute)
                DatePicker("End",   selection: $newEnd,   displayedComponents: .hourAndMinute)
            }
            Button(action: addRecurring) {
                Text("Add recurring rule")
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(newDays.isEmpty)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.separator, lineWidth: 1))
        )
    }

    @ViewBuilder private var addOneOffForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add one-off rule").font(Theme.headline).foregroundStyle(Theme.primaryText)
            HStack {
                DatePicker("Start", selection: $oneOffStart)
                DatePicker("End",   selection: $oneOffEnd)
            }
            Button(action: addOneOff) {
                Text("Add one-off rule")
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(oneOffEnd <= oneOffStart)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.separator, lineWidth: 1))
        )
    }

    // MARK: -

    private func addRecurring() {
        let calendar = Calendar.current
        let s = calendar.dateComponents([.hour, .minute], from: newStart)
        let e = calendar.dateComponents([.hour, .minute], from: newEnd)
        let rule: RecordingScheduleRule = .recurring(
            id: UUID(),
            days: newDays,
            start: ClockTime(hour: s.hour ?? 0, minute: s.minute ?? 0),
            end: ClockTime(hour: e.hour ?? 0, minute: e.minute ?? 0)
        )
        var schedule = settings.recordingSchedule ?? .empty
        schedule.rules.append(rule)
        settings.recordingSchedule = schedule
        newDays = []
    }

    private func addOneOff() {
        let rule: RecordingScheduleRule = .oneOff(id: UUID(), start: oneOffStart, end: oneOffEnd)
        var schedule = settings.recordingSchedule ?? .empty
        schedule.rules.append(rule)
        settings.recordingSchedule = schedule
    }

    private func removeRule(_ id: UUID) {
        guard var schedule = settings.recordingSchedule else { return }
        schedule.rules.removeAll { $0.id == id }
        settings.recordingSchedule = schedule.rules.isEmpty ? nil : schedule
    }
}

private extension RecordingScheduleRule {
    var isRecurring: Bool {
        if case .recurring = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .recurring(_, let days, let start, let end):
            let dayList = Weekday.allCases.filter { days.contains($0) }.map(\.shortName).joined(separator: " ")
            return "\(dayList.isEmpty ? "—" : dayList)  ·  \(start.formatted()) – \(end.formatted())"
        case .oneOff(_, let start, let end):
            let f: (Date) -> String = { $0.formatted(date: .abbreviated, time: .shortened) }
            return "Once  ·  \(f(start)) – \(f(end))"
        }
    }
}
