import SwiftUI

// MARK: - SchedulePickerView
//
// Sheet that lets a user configure a cron-based schedule for any TaskRecord.
// Shows human-readable presets + a custom cron input field.
// Saves to TaskScheduleStore on confirm.

struct SchedulePickerView: View {

    let taskID: String
    let taskTitle: String
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: SchedulePreset = .daily
    @State private var hour: Int = 9
    @State private var minute: Int = 0
    @State private var dayOfWeek: Int = 1          // Mon
    @State private var customCron: String = ""
    @State private var isCustom = false
    @State private var isEnabled = true
    @State private var previewText = ""

    // MARK: - Presets

    enum SchedulePreset: String, CaseIterable, Identifiable {
        case everyHour   = "Every Hour"
        case daily       = "Daily"
        case weekdays    = "Weekdays"
        case weekly      = "Weekly"
        case custom      = "Custom"
        var id: String { rawValue }
    }

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.12).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                GlassDivider()
                ScrollView {
                    VStack(spacing: 20) {
                        presetPicker
                        if selectedPreset != .everyHour {
                            timePicker
                        }
                        if selectedPreset == .weekly {
                            dayPicker
                        }
                        if selectedPreset == .custom {
                            customCronInput
                        }
                        previewCard
                        enableToggle
                    }
                    .padding(20)
                }
                GlassDivider()
                actionBar
            }
        }
        .onAppear { loadExisting(); updatePreview() }
        .onChange(of: selectedPreset) { _ in updatePreview() }
        .onChange(of: hour) { _ in updatePreview() }
        .onChange(of: minute) { _ in updatePreview() }
        .onChange(of: dayOfWeek) { _ in updatePreview() }
        .onChange(of: customCron) { _ in updatePreview() }
        .frame(width: 360)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Schedule Task")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Glass.textPrimary)
                Text(taskTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Glass.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Preset Picker

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Frequency")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(SchedulePreset.allCases) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedPreset = preset
                        }
                    } label: {
                        Text(preset.rawValue)
                            .font(.system(size: 12, weight: selectedPreset == preset ? .semibold : .regular))
                            .foregroundStyle(selectedPreset == preset ? Glass.textPrimary : Glass.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedPreset == preset ? Color.cyan.opacity(0.15) : Glass.backgroundDark)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedPreset == preset ? Color.cyan.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Time Picker

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Time")
            HStack(spacing: 12) {
                // Hour
                VStack(spacing: 4) {
                    Text("Hour")
                        .font(.system(size: 10))
                        .foregroundStyle(Glass.textTertiary)
                    Picker("Hour", selection: $hour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 70, height: 80)
                    .clipped()
                }

                Text(":")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Glass.textSecondary)

                // Minute
                VStack(spacing: 4) {
                    Text("Min")
                        .font(.system(size: 10))
                        .foregroundStyle(Glass.textTertiary)
                    Picker("Minute", selection: $minute) {
                        ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 70, height: 80)
                    .clipped()
                }

                Spacer()
            }
        }
    }

    // MARK: - Day Picker

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Day of Week")
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { day in
                    Button {
                        dayOfWeek = day
                    } label: {
                        Text(Self.dayNames[day])
                            .font(.system(size: 11, weight: dayOfWeek == day ? .semibold : .regular))
                            .foregroundStyle(dayOfWeek == day ? Glass.textPrimary : Glass.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(dayOfWeek == day ? Color.cyan.opacity(0.15) : Glass.backgroundDark)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Custom Cron

    private var customCronInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Cron Expression")
            TextField("* * * * *", text: $customCron)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Glass.textPrimary)
                .padding(10)
                .background(Glass.backgroundDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            CronEvaluator.isValid(customCron) ? Color.cyan.opacity(0.3) : Color.red.opacity(0.4),
                            lineWidth: 1
                        )
                )
                .cornerRadius(8)
                .autocorrectionDisabled()

            Text("Format: minute hour dayOfMonth month dayOfWeek")
                .font(.system(size: 10))
                .foregroundStyle(Glass.textTertiary)
        }
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        LiquidGlassCard(tint: .cyan) {
            HStack(spacing: 10) {
                GlassIconBadge("calendar.badge.clock", size: 28, tint: .cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Schedule Preview")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Glass.textSecondary)
                    Text(previewText.isEmpty ? "—" : previewText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Glass.textPrimary)
                    if let expr = currentExpression, !previewText.isEmpty,
                       let next = CronEvaluator.nextDate(from: expr) {
                        Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10))
                            .foregroundStyle(Glass.textTertiary)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Enable Toggle

    private var enableToggle: some View {
        HStack {
            Text("Enable schedule")
                .font(.system(size: 13))
                .foregroundStyle(Glass.textSecondary)
            Spacer()
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .cyan))
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            // Remove schedule (only if one exists)
            if TaskScheduleStore.shared.schedule(for: taskID) != nil {
                Button("Remove") {
                    TaskScheduleStore.shared.delete(taskID: taskID)
                    NotificationCenter.default.post(name: .capabilityStoreDidChange, object: nil)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.red.opacity(0.7))
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Glass.textSecondary)

            GlassButton("Save", icon: "checkmark", tint: .cyan) {
                save()
            }
            .disabled(currentExpression == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Glass.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var currentExpression: String? {
        let expr = buildExpression()
        return CronEvaluator.isValid(expr) ? expr : nil
    }

    private func buildExpression() -> String {
        switch selectedPreset {
        case .everyHour:
            return "0 * * * *"
        case .daily:
            return "\(minute) \(hour) * * *"
        case .weekdays:
            return "\(minute) \(hour) * * 1-5"
        case .weekly:
            return "\(minute) \(hour) * * \(dayOfWeek)"
        case .custom:
            return customCron.trimmingCharacters(in: .whitespaces)
        }
    }

    private func updatePreview() {
        let expr = buildExpression()
        if CronEvaluator.isValid(expr) {
            previewText = CronEvaluator.humanReadable(expr)
        } else {
            previewText = selectedPreset == .custom ? "Invalid expression" : ""
        }
    }

    private func loadExisting() {
        guard let existing = TaskScheduleStore.shared.schedule(for: taskID) else { return }
        isEnabled = existing.enabled
        customCron = existing.cronExpression
        selectedPreset = .custom
        updatePreview()
    }

    private func save() {
        guard let expr = currentExpression else { return }
        let schedule = TaskSchedule(
            id: taskID,
            taskID: taskID,
            cronExpression: expr,
            enabled: isEnabled,
            lastFiredAt: nil,
            createdAt: Date()
        )
        TaskScheduleStore.shared.save(schedule)
        NotificationCenter.default.post(name: .capabilityStoreDidChange, object: nil)
        dismiss()
    }
}
