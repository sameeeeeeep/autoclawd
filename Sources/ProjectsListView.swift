import SwiftUI

// MARK: - Projects List View

/// Main panel view showing all projects with their sessions.
struct ProjectsListView: View {
    @ObservedObject var appState: AppState
    @State private var selectedProjectID: String? = nil
    @State private var showAddProject = false

    var body: some View {
        NavigationSplitView {
            projectSidebar
        } detail: {
            if let projectID = selectedProjectID,
               let project = appState.projects.first(where: { $0.id == projectID }) {
                ProjectDetailView(project: project)
            } else {
                Text("Select a project")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showAddProject) {
            AddProjectSheet(isPresented: $showAddProject) { name, path in
                _ = appState.projectStore.insert(name: name, localPath: path)
                appState.projects = appState.projectStore.all()
            }
        }
    }

    // MARK: - Project Sidebar

    private var projectSidebar: some View {
        List(appState.projects, selection: $selectedProjectID) { project in
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(project.localPath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .tag(project.id)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
        .safeAreaInset(edge: .bottom) {
            Button {
                showAddProject = true
            } label: {
                Label("Add Project", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Project Detail View

/// Shows sessions for a project with summaries.
struct ProjectDetailView: View {
    let project: Project
    @State private var sessions: [SessionRecord] = []

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.title2.weight(.semibold))
                    Text(project.localPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Sessions list
            if sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No sessions recorded yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Start a session with this project selected to see it here.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(sessions) { session in
                            SessionRowView(session: session)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: project.id) { _ in reload() }
    }

    private func reload() {
        sessions = SessionStore.shared.sessions(forProjectID: project.id)
    }
}

// MARK: - Session Row View

/// A single session row with summary, time, people, and transcript snippet.
struct SessionRowView: View {
    let session: SessionRecord
    @State private var isExpanded = false

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()

    /// Build a human-readable session title from context or transcript snippet.
    private var sessionTitle: String {
        // Use context bullets as summary if available
        if let obj = session.objective,
           let data = obj.data(using: .utf8),
           let bullets = try? JSONDecoder().decode([String].self, from: data),
           let first = bullets.first, !first.isEmpty {
            return bullets.joined(separator: " · ")
        }
        // Fall back to transcript snippet
        let snippet = session.transcriptSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !snippet.isEmpty {
            return snippet
        }
        return "Untitled session"
    }

    /// Parse people names from JSON.
    private var peopleNames: [String] {
        guard let json = session.peopleJSON,
              let data = json.data(using: .utf8),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return names
    }

    /// Duration string.
    private var durationString: String? {
        guard let end = session.endedAt else { return nil }
        let seconds = Int(end.timeIntervalSince(session.startedAt))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    // Status dot
                    Circle()
                        .fill(session.endedAt != nil ? Color.green.opacity(0.6) : Color.orange)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        // Title
                        Text(sessionTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(isExpanded ? nil : 2)

                        // Metadata row
                        HStack(spacing: 8) {
                            Text(Self.timeFmt.string(from: session.startedAt))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            if let dur = durationString {
                                Text(dur)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }

                            if !peopleNames.isEmpty {
                                HStack(spacing: 2) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 8))
                                    Text(peopleNames.joined(separator: ", "))
                                        .lineLimit(1)
                                }
                                .font(.system(size: 10))
                                .foregroundColor(.blue.opacity(0.7))
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded: full transcript snippet
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !session.transcriptSnippet.isEmpty {
                        Text(session.transcriptSnippet)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                    }

                    if let place = session.placeName {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 9))
                            Text(place)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.green.opacity(0.7))
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 10)
            }

            Divider().padding(.leading, 36)
        }
    }
}
