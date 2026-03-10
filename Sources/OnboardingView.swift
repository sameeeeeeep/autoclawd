import SwiftUI

// MARK: - OnboardingView

/// Five-page liquid glass onboarding flow explaining AutoClawd's key wow moments.
/// Shown on first launch before the dependency setup screen.
struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var appeared = false
    var onComplete: (() -> Void)?

    private let pageCount = 5

    var body: some View {
        ZStack {
            // Full-screen ambient background
            Glass.ambientGradient
                .ignoresSafeArea()

            // Subtle floating orbs for depth
            backgroundOrbs

            VStack(spacing: 0) {
                // Skip button (top-right)
                HStack {
                    Spacer()
                    if currentPage < pageCount - 1 {
                        GlassChip("Skip", icon: "forward.fill") {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                currentPage = pageCount - 1
                            }
                        }
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.8), value: appeared)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .frame(height: 52)

                Spacer()

                // Page content
                ZStack {
                    ForEach(0..<pageCount, id: \.self) { index in
                        pageContent(for: index)
                            .opacity(currentPage == index ? 1 : 0)
                            .offset(x: CGFloat(index - currentPage) * 40)
                            .scaleEffect(currentPage == index ? 1 : 0.95)
                            .animation(.easeInOut(duration: 0.45), value: currentPage)
                    }
                }
                .frame(maxWidth: 520)

                Spacer()

                // Navigation: dots + next button
                HStack {
                    Spacer()
                    GlassProgressDots(count: pageCount, current: currentPage)
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    if currentPage < pageCount - 1 {
                        GlassButton("Next", icon: "arrow.right") {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                currentPage += 1
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 700, height: 600)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                appeared = true
            }
        }
    }

    // MARK: - Page Content

    @ViewBuilder
    private func pageContent(for index: Int) -> some View {
        switch index {
        case 0: welcomePage
        case 1: speakNaturallyPage
        case 2: watchItWorkPage
        case 3: tasksAutoExecutePage
        case 4: learnsAboutYouPage
        default: EmptyView()
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            // Logo / wordmark
            GlassIconBadge("waveform.circle.fill", size: 80, tint: .cyan)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2), value: appeared)

            VStack(spacing: 12) {
                Text("AUTOCLAWD")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(Glass.textPrimary)

                Text("Your ambient AI that listens, learns, and acts")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Glass.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(.easeOut(duration: 0.7).delay(0.4), value: appeared)

            GlassButton("Get Started", icon: "arrow.right", tint: .cyan, isLarge: true) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentPage = 1
                }
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.8), value: appeared)
        }
        .padding(40)
    }

    // MARK: - Page 2: Speak Naturally

    private var speakNaturallyPage: some View {
        LiquidGlassCard(cornerRadius: Glass.radiusLarge, tint: .cyan) {
            VStack(spacing: 24) {
                GlassIconBadge("mic.fill", size: 56, tint: .cyan)

                GlassWaveform(barCount: 9, tint: .cyan)
                    .frame(height: 40)

                VStack(spacing: 10) {
                    Text("Speak Naturally")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Glass.textPrimary)

                    Text("AutoClawd listens to your conversations and meetings with an always-on microphone.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Glass.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)

                    Text("No prompts. No typing. Just talk.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.cyan.opacity(0.7))
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Page 3: Watch It Work

    private var watchItWorkPage: some View {
        LiquidGlassCard(cornerRadius: Glass.radiusLarge, tint: .purple) {
            VStack(spacing: 24) {
                GlassIconBadge("brain.head.profile", size: 56, tint: .purple)

                GlassPipelineFlow()
                    .padding(.vertical, 4)

                VStack(spacing: 10) {
                    Text("Watch It Work")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Glass.textPrimary)

                    Text("Your words become clean transcripts, analyzed for context. Projects, people, and priorities — all detected automatically.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Glass.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Page 4: Tasks Auto-Execute

    private var tasksAutoExecutePage: some View {
        LiquidGlassCard(cornerRadius: Glass.radiusLarge, tint: .green) {
            VStack(spacing: 24) {
                GlassIconBadge("bolt.fill", size: 56, tint: .green)

                // Mock task cards
                VStack(spacing: 8) {
                    mockTaskCard(title: "Send project update email", status: "Completed", color: .green)
                    mockTaskCard(title: "Create GitHub PR for fix", status: "Running...", color: .cyan)
                    mockTaskCard(title: "Schedule standup meeting", status: "Queued", color: .orange)
                }

                VStack(spacing: 10) {
                    Text("Tasks Auto-Execute")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Glass.textPrimary)

                    Text("Detected tasks run via Claude Code — without you lifting a finger. Send emails, create PRs, fix bugs, all from a conversation.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Glass.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
    }

    private func mockTaskCard(title: String, status: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Glass.textPrimary)
            Spacer()
            Text(status)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Page 5: It Learns About You

    private var learnsAboutYouPage: some View {
        LiquidGlassCard(cornerRadius: Glass.radiusLarge, tint: .orange) {
            VStack(spacing: 24) {
                GlassIconBadge("person.crop.circle.badge.checkmark", size: 56, tint: .orange)

                // Knowledge nodes mockup
                HStack(spacing: 12) {
                    knowledgeNode("Projects", icon: "folder.fill", tint: .cyan)
                    knowledgeNode("People", icon: "person.2.fill", tint: .purple)
                    knowledgeNode("Context", icon: "location.fill", tint: .green)
                    knowledgeNode("Habits", icon: "heart.fill", tint: .orange)
                }

                VStack(spacing: 10) {
                    Text("It Learns About You")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Glass.textPrimary)

                    Text("A persistent world model builds from every conversation. Your projects, preferences, and context — always remembered.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Glass.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                GlassButton("Let's Set You Up", icon: "arrow.right", tint: .orange, isLarge: true) {
                    completeOnboarding()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
    }

    private func knowledgeNode(_ label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            GlassIconBadge(icon, size: 32, tint: tint)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Glass.textTertiary)
        }
    }

    // MARK: - Background Orbs

    private var backgroundOrbs: some View {
        ZStack {
            // Top-left cyan orb
            Circle()
                .fill(Color.cyan.opacity(0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -120, y: -160)

            // Bottom-right purple orb
            Circle()
                .fill(Color.purple.opacity(0.05))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: 140, y: 180)

            // Center warm orb
            Circle()
                .fill(Color.orange.opacity(0.03))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: 40, y: 20)
        }
    }

    // MARK: - Actions

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
        onComplete?()
    }
}
