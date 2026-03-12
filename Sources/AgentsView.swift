import SwiftUI

// MARK: - AgentsView
//
// Neo-brutalist agents dashboard with two tabs:
//   1. DISCOVER — browse the capability catalog, activate with one click
//   2. MY AGENTS — activated capabilities, ready to run
//
// Design: sharp edges, thick borders, bold type, high contrast.
// No soft rounded corners. Cards are div-like blocks.

struct AgentsView: View {

    @ObservedObject var appState: AppState
    @State private var capabilities: [Capability] = []
    @State private var runningID: String? = nil
    @State private var selectedTab: AgentsTab = .discover
    @State private var searchText: String = ""
    @State private var selectedCategory: CatalogCategory? = nil
    @State private var activatingID: String? = nil
    @State private var activationStatus: CatalogActivationService.ActivationStatus = .idle
    @State private var agentSearchText: String = ""
    @State private var selectedAgentCategory: CapabilityCategory? = nil

    private enum AgentsTab: String, CaseIterable {
        case discover = "DISCOVER"
        case myAgents = "MY AGENTS"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            brutalistDivider
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .capabilityStoreDidChange)) { _ in
            reload()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 0) {
                Text("AGENTS")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(.primary)
                    .tracking(2)

                Spacer()

                HStack(spacing: 4) {
                    Text("\(capabilities.filter(\.isAvailable).count)")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("/\(capabilities.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("ready")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06))
                .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1.5))
            }

            // Tab switcher
            HStack(spacing: 0) {
                ForEach(AgentsTab.allCases, id: \.self) { tab in
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { selectedTab = tab } }) {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .tracking(1.5)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.primary.opacity(0.08) : Color.clear)
                            .overlay(
                                Rectangle().stroke(
                                    selectedTab == tab ? Color.primary.opacity(0.2) : Color.clear,
                                    lineWidth: 1.5
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .discover:
            discoverView
        case .myAgents:
            myAgentsView
        }
    }

    // MARK: - Discover View

    private var discoverView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                TextField("Search tools...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.04))
            .overlay(Rectangle().stroke(Color.primary.opacity(0.12), lineWidth: 1.5))
            .padding(.horizontal, 20)
            .padding(.top, 14)

            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip(label: "ALL", category: nil)
                    ForEach(CatalogCategory.allCases, id: \.self) { cat in
                        categoryChip(label: cat.rawValue.uppercased(), category: cat)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }

            brutalistDivider

            // Catalog grid
            ScrollView {
                let entries = filteredCatalog
                if entries.isEmpty {
                    VStack(spacing: 10) {
                        Text("NO MATCHES")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .tracking(2)
                        Text("Try a different search or category")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(entries, id: \.id) { entry in
                            CatalogCard(
                                entry: entry,
                                isActivating: activatingID == entry.id,
                                activationStatus: activatingID == entry.id ? activationStatus : .idle,
                                onActivate: { activateEntry(entry) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - My Agents View

    @ViewBuilder
    private var myAgentsView: some View {
        if capabilities.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("Search agents...", text: $agentSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    if !agentSearchText.isEmpty {
                        Button(action: { agentSearchText = "" }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.04))
                .overlay(Rectangle().stroke(Color.primary.opacity(0.12), lineWidth: 1.5))
                .padding(.horizontal, 20)
                .padding(.top, 14)

                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        agentCategoryChip(label: "ALL", category: nil)
                        ForEach(agentCategoriesPresent, id: \.self) { cat in
                            agentCategoryChip(label: cat.label.uppercased(), category: cat)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }

                brutalistDivider

                // Agents grid
                ScrollView {
                    let filtered = filteredAgents
                    if filtered.isEmpty {
                        VStack(spacing: 10) {
                            Text("NO MATCHES")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .tracking(2)
                            Text("Try a different search or category")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ],
                            spacing: 10
                        ) {
                            ForEach(filtered) { cap in
                                BrutalistAgentCard(
                                    capability: cap,
                                    isRunning: runningID == cap.id,
                                    onRun: { runCapability(cap) }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
    }

    // MARK: - Agent Category Chip

    private func agentCategoryChip(label: String, category: CapabilityCategory?) -> some View {
        let isSelected = selectedAgentCategory == category
        return Button(action: {
            withAnimation(.easeOut(duration: 0.1)) {
                selectedAgentCategory = category
            }
        }) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                .overlay(
                    Rectangle().stroke(
                        isSelected ? Color.primary.opacity(0.25) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered Agents

    /// Categories present in the current capabilities list (only show chips that have content).
    private var agentCategoriesPresent: [CapabilityCategory] {
        let cats = Set(capabilities.map(\.category))
        return CapabilityCategory.allCases.filter { cats.contains($0) }
    }

    private var filteredAgents: [Capability] {
        var result = capabilities

        // Category filter
        if let cat = selectedAgentCategory {
            result = result.filter { $0.category == cat }
        }

        // Search filter
        if !agentSearchText.isEmpty {
            let lower = agentSearchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(lower) ||
                $0.description.lowercased().contains(lower) ||
                $0.slug.lowercased().contains(lower) ||
                $0.workflowTags.contains(where: { $0.lowercased().contains(lower) })
            }
        }

        // Sort: available first, then by name
        return result.sorted {
            if $0.isAvailable != $1.isAvailable { return $0.isAvailable }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("//")
                .font(.system(size: 48, weight: .black, design: .monospaced))
                .foregroundStyle(.tertiary)
            VStack(spacing: 8) {
                Text("NO AGENTS YET")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundStyle(.primary)
                    .tracking(2)
                Text("Switch to DISCOVER tab to browse and activate tools.\nOr use Learn mode to build capabilities from your workflow.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: { selectedTab = .discover }) {
                Text("BROWSE CATALOG")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.08))
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.2), lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Category Chip

    private func categoryChip(label: String, category: CatalogCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button(action: {
            withAnimation(.easeOut(duration: 0.1)) {
                selectedCategory = category
            }
        }) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                .overlay(
                    Rectangle().stroke(
                        isSelected ? Color.primary.opacity(0.25) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Brutalist Divider

    private var brutalistDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1.5)
    }

    // MARK: - Filtered Catalog

    private var filteredCatalog: [CatalogEntry] {
        var entries = CapabilityCatalog.all
        if let cat = selectedCategory {
            entries = entries.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            entries = CapabilityCatalog.search(searchText).filter { entry in
                selectedCategory == nil || entry.category == selectedCategory
            }
        }
        return entries
    }

    // MARK: - Actions

    private func reload() {
        capabilities = CapabilityStore.shared.all()
    }

    private func runCapability(_ cap: Capability) {
        runningID = cap.id
        appState.executeCapability(cap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if runningID == cap.id { runningID = nil }
        }
    }

    private func activateEntry(_ entry: CatalogEntry) {
        activatingID = entry.id
        activationStatus = .idle

        CatalogActivationService.shared.activate(entry) { [self] status in
            DispatchQueue.main.async {
                self.activationStatus = status
            }
        } onComplete: { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.activationStatus = .done
                    self.reload()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if self.activatingID == entry.id {
                            self.activatingID = nil
                            self.activationStatus = .idle
                        }
                    }
                case .failure(let error):
                    self.activationStatus = .failed(error.localizedDescription)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if self.activatingID == entry.id {
                            self.activatingID = nil
                            self.activationStatus = .idle
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CatalogCard (Neo-Brutalist)

struct CatalogCard: View {

    let entry: CatalogEntry
    let isActivating: Bool
    let activationStatus: CatalogActivationService.ActivationStatus
    let onActivate: () -> Void

    @State private var isHovered = false

    private var isActivated: Bool { entry.hasSkillMD }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Top row: emoji + install badge
            HStack(alignment: .center, spacing: 0) {
                Text(entry.emoji)
                    .font(.system(size: 22))
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.05))
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.1), lineWidth: 1))

                Spacer()

                installBadge
            }
            .padding(.bottom, 10)

            // Name
            Text(entry.name.uppercased())
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(.primary)
                .tracking(0.5)
                .lineLimit(1)
                .padding(.bottom, 4)

            // Description
            Text(entry.description)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            // Footer: category + action
            HStack(spacing: 0) {
                Text(entry.category.rawValue.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)

                Spacer()

                activateButton
            }
        }
        .padding(12)
        .frame(minHeight: 155)
        .background(isHovered ? Color.primary.opacity(0.04) : Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle().stroke(
                isHovered ? Color.primary.opacity(0.25) : Color.primary.opacity(0.10),
                lineWidth: isHovered ? 2 : 1.5
            )
        )
        .onHover { isHovered = $0 }
    }

    // MARK: - Install Badge

    private var installBadge: some View {
        Group {
            if entry.isInstalled {
                Text("INSTALLED")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                    .tracking(0.5)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .overlay(Rectangle().stroke(Color.green.opacity(0.3), lineWidth: 1))
            } else {
                Text(entry.install.label.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
        }
    }

    // MARK: - Activate Button

    @ViewBuilder
    private var activateButton: some View {
        if isActivated && !isActivating {
            // Already activated
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                Text("ACTIVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .overlay(Rectangle().stroke(Color.green.opacity(0.3), lineWidth: 1.5))
        } else if isActivating {
            // Activating
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Text(statusLabel)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .overlay(Rectangle().stroke(Color.orange.opacity(0.3), lineWidth: 1.5))
        } else {
            // Not activated — show activate button
            Button(action: onActivate) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                    Text("ACTIVATE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(isHovered ? 0.1 : 0.06))
                .overlay(Rectangle().stroke(Color.primary.opacity(0.2), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    private var statusLabel: String {
        switch activationStatus {
        case .idle, .checking:            return "CHECKING..."
        case .installing:                 return "INSTALLING..."
        case .writingSkill:               return "WRITING..."
        case .registeringCapability:      return "REGISTERING..."
        case .done:                       return "DONE"
        case .failed:                     return "FAILED"
        }
    }
}

// MARK: - BrutalistAgentCard (Neo-Brutalist)

/// Unified capability card — shows availability, source, deps, run/install actions.
struct BrutalistAgentCard: View {

    let capability: Capability
    let isRunning: Bool
    let onRun: () -> Void

    @State private var isHovered = false

    private var isAvailable: Bool { capability.isAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Top: emoji + availability dot + action button
            HStack(alignment: .center, spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    Text(capability.emoji)
                        .font(.system(size: 22))
                        .frame(width: 36, height: 36)
                        .background(categoryColor.opacity(0.1))
                        .overlay(Rectangle().stroke(categoryColor.opacity(0.3), lineWidth: 1.5))

                    // Availability dot
                    Circle()
                        .fill(isAvailable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color(NSColor.controlBackgroundColor), lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }

                Spacer()

                actionButton
            }
            .padding(.bottom, 10)

            // Name
            Text(capability.name.uppercased())
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(isAvailable ? .primary : .secondary)
                .tracking(0.5)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            // Description
            Text(capability.description)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            // Missing deps warning
            if !isAvailable {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                    Text("Missing: \(capability.missingDeps.joined(separator: ", "))")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 10)

            // Footer: source badge + category
            HStack(spacing: 6) {
                sourceBadge

                Spacer()

                Text(capability.category.label.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(categoryColor.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(categoryColor.opacity(0.08))
                    .overlay(Rectangle().stroke(categoryColor.opacity(0.2), lineWidth: 1))
            }
        }
        .padding(12)
        .frame(minHeight: 155)
        .background(isHovered ? Color.primary.opacity(0.04) : Color(NSColor.controlBackgroundColor))
        .opacity(isAvailable ? 1.0 : 0.75)
        .overlay(
            Rectangle().stroke(
                isHovered ? categoryColor.opacity(0.4) : Color.primary.opacity(0.10),
                lineWidth: isHovered ? 2 : 1.5
            )
        )
        .onHover { isHovered = $0 }
    }

    // MARK: - Action Button (Run or Install)

    @ViewBuilder
    private var actionButton: some View {
        if isAvailable {
            // Run button
            Button(action: onRun) {
                Group {
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .foregroundStyle(isHovered ? categoryColor : .secondary)
                .frame(width: 32, height: 32)
                .background(isHovered ? categoryColor.opacity(0.12) : Color.primary.opacity(0.05))
                .overlay(
                    Rectangle().stroke(
                        isHovered ? categoryColor.opacity(0.3) : Color.primary.opacity(0.1),
                        lineWidth: 1.5
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
        } else {
            // Install button for unavailable capabilities
            Button(action: { /* Install flow handled by parent via CatalogActivationService */ }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("INSTALL")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.08))
                .overlay(Rectangle().stroke(Color.orange.opacity(0.3), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Source Badge

    private var sourceBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: sourceIcon)
                .font(.system(size: 7, weight: .bold))
            Text(sourceLabel)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.3)
        }
        .foregroundStyle(sourceColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .overlay(Rectangle().stroke(sourceColor.opacity(0.3), lineWidth: 1))
    }

    private var sourceLabel: String {
        switch capability.source {
        case .openclaw:  return "OPENCLAW"
        case .fucbc:     return "LEARNED"
        case .catalog:   return "CATALOG"
        case .builtin:   return "BUILT-IN"
        }
    }

    private var sourceIcon: String {
        switch capability.source {
        case .openclaw:  return "doc.text"
        case .fucbc:     return "brain"
        case .catalog:   return "square.grid.2x2"
        case .builtin:   return "cpu"
        }
    }

    private var sourceColor: Color {
        switch capability.source {
        case .openclaw:  return .cyan
        case .fucbc:     return .purple
        case .catalog:   return .orange
        case .builtin:   return .secondary
        }
    }

    // MARK: - Helpers

    private var categoryColor: Color {
        switch capability.category {
        case .research:      return .blue
        case .automation:    return .purple
        case .communication: return .green
        case .development:   return .orange
        case .discovery:     return .cyan
        case .organization:  return .indigo
        case .creative:      return .pink
        case .search:        return .teal
        case .analysis:      return .mint
        case .marketing:     return .red
        case .system:        return .gray
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let capabilityStoreDidChange = Notification.Name("capabilityStoreDidChange")
}
