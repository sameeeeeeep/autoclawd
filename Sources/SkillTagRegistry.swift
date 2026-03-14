import Foundation

// MARK: - SkillTagRegistry
//
// Comprehensive tag index for all 144+ OpenClaw skills.
// Maps skill slugs → trigger metadata (apps, URLs, keywords, workflow tags, category).
//
// This feeds into the suggestion system so AutoClawd can match the right
// skills to the user's current context (screen OCR, active app, URLs, voice).
//
// Tags live here — not in individual SKILL.md files — because:
//   1. Single source of truth for all trigger metadata
//   2. No need to modify 144 files
//   3. Fast O(1) lookup by slug
//   4. Easy to extend and maintain

struct SkillTags {
    let apps: [String]              // app names that trigger this skill
    let urls: [String]              // URL patterns
    let keywords: [String]          // voice/OCR keywords
    let workflowTags: [String]      // for WorkflowBuilder matching
    let category: String            // broad category
}

struct SkillTagRegistry {

    // MARK: - Lookup

    static func tags(for slug: String) -> SkillTags? {
        index[slug]
    }

    /// All slugs for a given workflow tag.
    static func forWorkflowTag(_ tag: String) -> [String] {
        let lower = tag.lowercased()
        return index.compactMap { slug, tags in
            tags.workflowTags.contains(where: { $0.lowercased() == lower }) ? slug : nil
        }
    }

    /// All slugs for a given category.
    static func forCategory(_ category: String) -> [String] {
        let lower = category.lowercased()
        return index.compactMap { slug, tags in
            tags.category.lowercased() == lower ? slug : nil
        }
    }

    // MARK: - The Index

    static let index: [String: SkillTags] = [

        // ── Research & Knowledge ─────────────────────────────────────────

        "academic-deep-research": SkillTags(
            apps: ["Safari", "Chrome", "Arc"],
            urls: ["scholar.google.com", "arxiv.org", "pubmed.ncbi", "jstor.org", "semanticscholar.org"],
            keywords: ["research", "literature review", "academic", "paper", "study", "citation", "deep research", "competitive analysis"],
            workflowTags: ["research", "content-creation", "analysis"],
            category: "research"
        ),

        "summarize": SkillTags(
            apps: ["Safari", "Chrome", "Arc"],
            urls: ["youtube.com", "youtu.be"],
            keywords: ["summarize", "summary", "tldr", "key points", "digest", "transcribe", "podcast"],
            workflowTags: ["content-analysis", "research", "transcription"],
            category: "research"
        ),

        "oracle": SkillTags(
            apps: ["Terminal", "iTerm2"],
            urls: [],
            keywords: ["oracle", "prompt", "query", "ask ai"],
            workflowTags: ["ai-processing", "research"],
            category: "ai"
        ),

        "blogwatcher": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: [],
            keywords: ["blog", "rss", "feed", "monitor", "updates", "news"],
            workflowTags: ["research", "monitoring"],
            category: "research"
        ),

        "xurl": SkillTags(
            apps: ["Safari", "Chrome", "Arc"],
            urls: ["x.com", "twitter.com"],
            keywords: ["tweet", "post", "x.com", "twitter", "reply", "dm", "followers"],
            workflowTags: ["social-media", "communication", "content-creation"],
            category: "social-media"
        ),

        // ── Communication ────────────────────────────────────────────────

        "slack": SkillTags(
            apps: ["Slack"],
            urls: ["slack.com", "app.slack.com"],
            keywords: ["slack", "send message", "notify team", "channel", "post update"],
            workflowTags: ["communication", "team-collaboration"],
            category: "communication"
        ),

        "discord": SkillTags(
            apps: ["Discord"],
            urls: ["discord.com", "discord.gg"],
            keywords: ["discord", "server", "channel", "message"],
            workflowTags: ["communication", "team-collaboration"],
            category: "communication"
        ),

        "imsg": SkillTags(
            apps: ["Messages"],
            urls: [],
            keywords: ["imessage", "text", "sms", "message", "send text"],
            workflowTags: ["communication", "personal"],
            category: "communication"
        ),

        "bluebubbles": SkillTags(
            apps: ["Messages", "BlueBubbles"],
            urls: [],
            keywords: ["imessage", "text", "sms", "message", "send text"],
            workflowTags: ["communication", "personal"],
            category: "communication"
        ),

        "himalaya": SkillTags(
            apps: ["Mail"],
            urls: ["mail.google.com", "outlook.live.com"],
            keywords: ["email", "inbox", "send email", "reply", "forward", "imap"],
            workflowTags: ["communication", "email", "productivity"],
            category: "communication"
        ),

        "custom-smtp-sender": SkillTags(
            apps: ["Mail"],
            urls: [],
            keywords: ["send email", "smtp", "email", "newsletter"],
            workflowTags: ["communication", "email", "automation"],
            category: "communication"
        ),

        "voice-call": SkillTags(
            apps: [],
            urls: [],
            keywords: ["voice call", "call", "phone", "speak"],
            workflowTags: ["communication"],
            category: "communication"
        ),

        // ── Notes & Knowledge Management ─────────────────────────────────

        "apple-notes": SkillTags(
            apps: ["Notes"],
            urls: [],
            keywords: ["note", "notes", "write note", "save note", "apple notes"],
            workflowTags: ["notes", "productivity", "personal"],
            category: "notes"
        ),

        "bear-notes": SkillTags(
            apps: ["Bear"],
            urls: [],
            keywords: ["bear", "note", "write note", "markdown note"],
            workflowTags: ["notes", "productivity"],
            category: "notes"
        ),

        "notion": SkillTags(
            apps: ["Notion"],
            urls: ["notion.so", "notion.site"],
            keywords: ["notion", "page", "database", "wiki", "workspace"],
            workflowTags: ["notes", "productivity", "project-management"],
            category: "notes"
        ),

        "obsidian": SkillTags(
            apps: ["Obsidian"],
            urls: [],
            keywords: ["obsidian", "vault", "note", "knowledge base", "zettelkasten"],
            workflowTags: ["notes", "productivity", "research"],
            category: "notes"
        ),

        "apple-reminders": SkillTags(
            apps: ["Reminders"],
            urls: [],
            keywords: ["reminder", "remind me", "reminders", "due", "alert"],
            workflowTags: ["productivity", "personal", "task-management"],
            category: "productivity"
        ),

        "things-mac": SkillTags(
            apps: ["Things"],
            urls: [],
            keywords: ["things", "todo", "task", "inbox", "today", "upcoming"],
            workflowTags: ["productivity", "task-management", "personal"],
            category: "productivity"
        ),

        // ── Development & GitHub ─────────────────────────────────────────

        "coding-agent": SkillTags(
            apps: ["Terminal", "iTerm2", "Xcode", "VS Code", "Cursor"],
            urls: ["github.com", "gitlab.com"],
            keywords: ["code", "build", "create", "implement", "fix bug", "refactor", "coding agent", "codex", "claude code"],
            workflowTags: ["development", "coding", "automation"],
            category: "development"
        ),

        "github": SkillTags(
            apps: ["Safari", "Chrome", "Arc"],
            urls: ["github.com"],
            keywords: ["github", "repo", "repository", "clone", "star", "fork"],
            workflowTags: ["development", "git", "project-management"],
            category: "development"
        ),

        "gh-issues": SkillTags(
            apps: ["Safari", "Chrome", "Arc", "Terminal"],
            urls: ["github.com"],
            keywords: ["issue", "bug", "fix issue", "github issue", "pr", "pull request", "review"],
            workflowTags: ["development", "git", "project-management", "automation"],
            category: "development"
        ),

        "skill-creator": SkillTags(
            apps: ["Terminal"],
            urls: [],
            keywords: ["create skill", "new skill", "skill creator", "package skill"],
            workflowTags: ["development", "automation"],
            category: "development"
        ),

        "clawhub": SkillTags(
            apps: ["Terminal"],
            urls: ["clawhub.com"],
            keywords: ["clawhub", "install skill", "publish skill", "skill store"],
            workflowTags: ["development", "automation"],
            category: "development"
        ),

        "mcporter": SkillTags(
            apps: ["Terminal"],
            urls: [],
            keywords: ["mcp", "mcp server", "tool", "mcp tool"],
            workflowTags: ["development", "automation"],
            category: "development"
        ),

        // ── Google Workspace ─────────────────────────────────────────────

        "gws-gmail": SkillTags(
            apps: ["Safari", "Chrome", "Mail"],
            urls: ["mail.google.com"],
            keywords: ["gmail", "email", "inbox", "send email", "read email"],
            workflowTags: ["email", "communication", "productivity"],
            category: "google-workspace"
        ),

        "gws-gmail-send": SkillTags(
            apps: ["Safari", "Chrome", "Mail"],
            urls: ["mail.google.com"],
            keywords: ["send email", "gmail", "compose", "write email"],
            workflowTags: ["email", "communication"],
            category: "google-workspace"
        ),

        "gws-gmail-triage": SkillTags(
            apps: ["Safari", "Chrome", "Mail"],
            urls: ["mail.google.com"],
            keywords: ["inbox", "unread", "triage", "email summary"],
            workflowTags: ["email", "productivity"],
            category: "google-workspace"
        ),

        "gws-gmail-watch": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["mail.google.com"],
            keywords: ["watch email", "email notifications", "new email"],
            workflowTags: ["email", "monitoring"],
            category: "google-workspace"
        ),

        "gws-calendar": SkillTags(
            apps: ["Calendar", "Safari", "Chrome"],
            urls: ["calendar.google.com"],
            keywords: ["calendar", "event", "schedule", "meeting", "appointment"],
            workflowTags: ["calendar", "productivity", "scheduling"],
            category: "google-workspace"
        ),

        "gws-calendar-agenda": SkillTags(
            apps: ["Calendar", "Safari", "Chrome"],
            urls: ["calendar.google.com"],
            keywords: ["agenda", "upcoming", "what's next", "schedule today", "meetings today"],
            workflowTags: ["calendar", "productivity"],
            category: "google-workspace"
        ),

        "gws-calendar-insert": SkillTags(
            apps: ["Calendar", "Safari", "Chrome"],
            urls: ["calendar.google.com"],
            keywords: ["create event", "new event", "schedule meeting", "add to calendar", "book time"],
            workflowTags: ["calendar", "scheduling"],
            category: "google-workspace"
        ),

        "gws-docs": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["docs.google.com"],
            keywords: ["google doc", "document", "write doc", "read doc"],
            workflowTags: ["content-creation", "productivity", "collaboration"],
            category: "google-workspace"
        ),

        "gws-docs-write": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["docs.google.com"],
            keywords: ["write to doc", "append doc", "add to document"],
            workflowTags: ["content-creation", "productivity"],
            category: "google-workspace"
        ),

        "gws-drive": SkillTags(
            apps: ["Finder", "Safari", "Chrome"],
            urls: ["drive.google.com"],
            keywords: ["google drive", "drive", "file", "folder", "shared drive"],
            workflowTags: ["file-management", "cloud-storage", "collaboration"],
            category: "google-workspace"
        ),

        "gws-drive-upload": SkillTags(
            apps: ["Finder", "Safari", "Chrome"],
            urls: ["drive.google.com"],
            keywords: ["upload", "upload to drive", "share file", "drive upload"],
            workflowTags: ["file-management", "cloud-storage"],
            category: "google-workspace"
        ),

        "gws-sheets": SkillTags(
            apps: ["Safari", "Chrome", "Numbers"],
            urls: ["sheets.google.com", "docs.google.com/spreadsheets"],
            keywords: ["spreadsheet", "google sheets", "sheet", "cells", "data"],
            workflowTags: ["data-processing", "productivity", "analytics"],
            category: "google-workspace"
        ),

        "gws-sheets-append": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["sheets.google.com", "docs.google.com/spreadsheets"],
            keywords: ["add row", "append row", "log to sheet", "add data"],
            workflowTags: ["data-processing", "productivity"],
            category: "google-workspace"
        ),

        "gws-sheets-read": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["sheets.google.com", "docs.google.com/spreadsheets"],
            keywords: ["read sheet", "get data", "sheet values"],
            workflowTags: ["data-processing", "productivity"],
            category: "google-workspace"
        ),

        "gws-slides": SkillTags(
            apps: ["Safari", "Chrome", "Keynote"],
            urls: ["docs.google.com/presentation"],
            keywords: ["slides", "presentation", "deck", "google slides"],
            workflowTags: ["content-creation", "presentations"],
            category: "google-workspace"
        ),

        "gws-tasks": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["tasks.google.com"],
            keywords: ["task", "todo", "task list", "google tasks", "add task"],
            workflowTags: ["task-management", "productivity"],
            category: "google-workspace"
        ),

        "gws-chat": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["chat.google.com"],
            keywords: ["google chat", "chat", "space", "team chat"],
            workflowTags: ["communication", "team-collaboration"],
            category: "google-workspace"
        ),

        "gws-chat-send": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["chat.google.com"],
            keywords: ["send chat", "post to chat", "message team"],
            workflowTags: ["communication", "team-collaboration"],
            category: "google-workspace"
        ),

        "gws-meet": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["meet.google.com"],
            keywords: ["google meet", "video call", "meeting", "conference"],
            workflowTags: ["communication", "meetings"],
            category: "google-workspace"
        ),

        "gws-forms": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["docs.google.com/forms"],
            keywords: ["form", "survey", "google form", "questionnaire"],
            workflowTags: ["data-collection", "productivity"],
            category: "google-workspace"
        ),

        "gws-keep": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["keep.google.com"],
            keywords: ["google keep", "quick note", "keep note"],
            workflowTags: ["notes", "productivity"],
            category: "google-workspace"
        ),

        "gws-people": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["contacts.google.com"],
            keywords: ["contacts", "people", "google contacts", "phone number", "address"],
            workflowTags: ["communication", "personal"],
            category: "google-workspace"
        ),

        "gws-classroom": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["classroom.google.com"],
            keywords: ["classroom", "course", "assignment", "student", "teacher"],
            workflowTags: ["education", "productivity"],
            category: "google-workspace"
        ),

        "gws-admin-reports": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["admin.google.com"],
            keywords: ["admin", "audit", "reports", "usage", "workspace admin"],
            workflowTags: ["admin", "monitoring"],
            category: "google-workspace"
        ),

        "gws-events": SkillTags(
            apps: [], urls: [],
            keywords: ["workspace events", "subscribe", "watch changes"],
            workflowTags: ["automation", "monitoring"],
            category: "google-workspace"
        ),

        "gws-events-renew": SkillTags(
            apps: [], urls: [],
            keywords: ["renew subscription", "reactivate watch"],
            workflowTags: ["automation", "monitoring"],
            category: "google-workspace"
        ),

        "gws-events-subscribe": SkillTags(
            apps: [], urls: [],
            keywords: ["subscribe events", "watch events", "stream events"],
            workflowTags: ["automation", "monitoring"],
            category: "google-workspace"
        ),

        "gws-shared": SkillTags(
            apps: [], urls: [],
            keywords: ["gws", "google workspace"],
            workflowTags: ["google-workspace"],
            category: "google-workspace"
        ),

        "gws-modelarmor": SkillTags(
            apps: [], urls: [],
            keywords: ["model armor", "content safety", "filter"],
            workflowTags: ["safety", "ai-processing"],
            category: "google-workspace"
        ),

        "gws-modelarmor-create-template": SkillTags(
            apps: [], urls: [],
            keywords: ["safety template", "model armor template"],
            workflowTags: ["safety", "ai-processing"],
            category: "google-workspace"
        ),

        "gws-modelarmor-sanitize-prompt": SkillTags(
            apps: [], urls: [],
            keywords: ["sanitize prompt", "filter prompt"],
            workflowTags: ["safety", "ai-processing"],
            category: "google-workspace"
        ),

        "gws-modelarmor-sanitize-response": SkillTags(
            apps: [], urls: [],
            keywords: ["sanitize response", "filter response"],
            workflowTags: ["safety", "ai-processing"],
            category: "google-workspace"
        ),

        "autoclawd-google-workspace": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["google.com", "gmail.com", "drive.google.com"],
            keywords: ["google workspace", "gws"],
            workflowTags: ["google-workspace", "productivity"],
            category: "google-workspace"
        ),

        "gog": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["google.com"],
            keywords: ["google workspace", "gmail", "calendar", "drive", "sheets"],
            workflowTags: ["google-workspace", "productivity"],
            category: "google-workspace"
        ),

        // ── GWS Workflows ───────────────────────────────────────────────

        "gws-workflow": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["google.com"],
            keywords: ["workflow", "automate", "google workflow"],
            workflowTags: ["automation", "productivity", "google-workspace"],
            category: "google-workspace"
        ),

        "gws-workflow-email-to-task": SkillTags(
            apps: ["Safari", "Chrome", "Mail"],
            urls: ["mail.google.com"],
            keywords: ["email to task", "convert email", "task from email"],
            workflowTags: ["email", "task-management", "automation"],
            category: "google-workspace"
        ),

        "gws-workflow-file-announce": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["drive.google.com"],
            keywords: ["announce file", "share file", "notify team"],
            workflowTags: ["communication", "file-management"],
            category: "google-workspace"
        ),

        "gws-workflow-meeting-prep": SkillTags(
            apps: ["Calendar", "Safari", "Chrome"],
            urls: ["calendar.google.com", "meet.google.com"],
            keywords: ["meeting prep", "prepare meeting", "agenda", "meeting notes"],
            workflowTags: ["meetings", "productivity"],
            category: "google-workspace"
        ),

        "gws-workflow-standup-report": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: [],
            keywords: ["standup", "daily standup", "status report", "daily report"],
            workflowTags: ["team-collaboration", "productivity"],
            category: "google-workspace"
        ),

        "gws-workflow-weekly-digest": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: [],
            keywords: ["weekly digest", "weekly report", "summary", "week recap"],
            workflowTags: ["productivity", "reporting"],
            category: "google-workspace"
        ),

        // ── GWS Recipes ─────────────────────────────────────────────────

        "recipe-backup-sheet-as-csv": SkillTags(
            apps: [], urls: ["sheets.google.com"],
            keywords: ["backup sheet", "export csv", "download sheet"],
            workflowTags: ["data-processing", "backup"], category: "google-workspace"
        ),
        "recipe-batch-invite-to-event": SkillTags(
            apps: ["Calendar"], urls: ["calendar.google.com"],
            keywords: ["invite", "batch invite", "add attendees"],
            workflowTags: ["calendar", "communication"], category: "google-workspace"
        ),
        "recipe-block-focus-time": SkillTags(
            apps: ["Calendar"], urls: ["calendar.google.com"],
            keywords: ["focus time", "block time", "deep work", "do not disturb"],
            workflowTags: ["calendar", "productivity"], category: "google-workspace"
        ),
        "recipe-bulk-download-folder": SkillTags(
            apps: ["Finder"], urls: ["drive.google.com"],
            keywords: ["download folder", "bulk download", "drive download"],
            workflowTags: ["file-management"], category: "google-workspace"
        ),
        "recipe-collect-form-responses": SkillTags(
            apps: [], urls: ["docs.google.com/forms"],
            keywords: ["form responses", "survey results", "collect responses"],
            workflowTags: ["data-collection"], category: "google-workspace"
        ),
        "recipe-compare-sheet-tabs": SkillTags(
            apps: [], urls: ["sheets.google.com"],
            keywords: ["compare sheets", "diff tabs", "sheet comparison"],
            workflowTags: ["data-processing", "analytics"], category: "google-workspace"
        ),
        "recipe-copy-sheet-for-new-month": SkillTags(
            apps: [], urls: ["sheets.google.com"],
            keywords: ["new month sheet", "copy sheet", "monthly template"],
            workflowTags: ["productivity", "templates"], category: "google-workspace"
        ),
        "recipe-create-classroom-course": SkillTags(
            apps: [], urls: ["classroom.google.com"],
            keywords: ["create course", "new class", "classroom"],
            workflowTags: ["education"], category: "google-workspace"
        ),
        "recipe-create-doc-from-template": SkillTags(
            apps: [], urls: ["docs.google.com"],
            keywords: ["doc template", "create from template", "new doc"],
            workflowTags: ["content-creation", "templates"], category: "google-workspace"
        ),
        "recipe-create-events-from-sheet": SkillTags(
            apps: ["Calendar"], urls: ["sheets.google.com", "calendar.google.com"],
            keywords: ["events from sheet", "bulk events", "import events"],
            workflowTags: ["calendar", "automation"], category: "google-workspace"
        ),
        "recipe-create-expense-tracker": SkillTags(
            apps: [], urls: ["sheets.google.com"],
            keywords: ["expense tracker", "track expenses", "budget"],
            workflowTags: ["finance", "productivity"], category: "google-workspace"
        ),
        "recipe-create-feedback-form": SkillTags(
            apps: [], urls: ["docs.google.com/forms"],
            keywords: ["feedback form", "create form", "survey"],
            workflowTags: ["data-collection", "communication"], category: "google-workspace"
        ),
        "recipe-create-gmail-filter": SkillTags(
            apps: [], urls: ["mail.google.com"],
            keywords: ["gmail filter", "email filter", "auto label"],
            workflowTags: ["email", "automation"], category: "google-workspace"
        ),
        "recipe-create-meet-space": SkillTags(
            apps: [], urls: ["meet.google.com"],
            keywords: ["create meeting", "new meet", "meeting room"],
            workflowTags: ["meetings", "communication"], category: "google-workspace"
        ),
        "recipe-create-presentation": SkillTags(
            apps: ["Keynote"], urls: ["docs.google.com/presentation"],
            keywords: ["create presentation", "new deck", "slides"],
            workflowTags: ["content-creation", "presentations"], category: "google-workspace"
        ),
        "recipe-create-shared-drive": SkillTags(
            apps: [], urls: ["drive.google.com"],
            keywords: ["shared drive", "team drive", "new drive"],
            workflowTags: ["file-management", "collaboration"], category: "google-workspace"
        ),
        "recipe-create-task-list": SkillTags(
            apps: [], urls: ["tasks.google.com"],
            keywords: ["task list", "new task list", "create tasks"],
            workflowTags: ["task-management"], category: "google-workspace"
        ),
        "recipe-create-vacation-responder": SkillTags(
            apps: [], urls: ["mail.google.com"],
            keywords: ["vacation responder", "out of office", "auto reply", "ooo"],
            workflowTags: ["email", "automation"], category: "google-workspace"
        ),
        "recipe-draft-email-from-doc": SkillTags(
            apps: [], urls: ["docs.google.com", "mail.google.com"],
            keywords: ["draft from doc", "email from document"],
            workflowTags: ["email", "content-creation"], category: "google-workspace"
        ),
        "recipe-email-drive-link": SkillTags(
            apps: [], urls: ["drive.google.com", "mail.google.com"],
            keywords: ["email link", "share drive link", "send file link"],
            workflowTags: ["email", "file-management"], category: "google-workspace"
        ),
        "recipe-find-free-time": SkillTags(
            apps: ["Calendar"], urls: ["calendar.google.com"],
            keywords: ["free time", "availability", "find slot", "when am I free"],
            workflowTags: ["calendar", "scheduling"], category: "google-workspace"
        ),
        "recipe-find-large-files": SkillTags(
            apps: ["Finder"], urls: ["drive.google.com"],
            keywords: ["large files", "storage", "drive cleanup", "disk space"],
            workflowTags: ["file-management", "cleanup"], category: "google-workspace"
        ),
        "recipe-forward-labeled-emails": SkillTags(
            apps: [], urls: ["mail.google.com"],
            keywords: ["forward emails", "labeled emails", "auto forward"],
            workflowTags: ["email", "automation"], category: "google-workspace"
        ),
        "recipe-generate-report-from-sheet": SkillTags(
            apps: [], urls: ["sheets.google.com"],
            keywords: ["generate report", "report from sheet", "analytics report"],
            workflowTags: ["reporting", "analytics"], category: "google-workspace"
        ),
        "recipe-label-and-archive-emails": SkillTags(
            apps: [], urls: ["mail.google.com"],
            keywords: ["label emails", "archive emails", "organize inbox"],
            workflowTags: ["email", "productivity"], category: "google-workspace"
        ),
        "recipe-log-deal-update": SkillTags(
            apps: [], urls: ["sheets.google.com"],
            keywords: ["log deal", "crm update", "sales log", "deal tracker"],
            workflowTags: ["sales", "data-processing"], category: "google-workspace"
        ),
        "recipe-organize-drive-folder": SkillTags(
            apps: ["Finder"], urls: ["drive.google.com"],
            keywords: ["organize folder", "clean up drive", "sort files"],
            workflowTags: ["file-management", "cleanup"], category: "google-workspace"
        ),
        "recipe-plan-weekly-schedule": SkillTags(
            apps: ["Calendar"], urls: ["calendar.google.com"],
            keywords: ["weekly schedule", "plan week", "weekly plan"],
            workflowTags: ["calendar", "productivity"], category: "google-workspace"
        ),
        "recipe-post-mortem-setup": SkillTags(
            apps: [], urls: ["docs.google.com"],
            keywords: ["post mortem", "retro", "retrospective", "incident review"],
            workflowTags: ["team-collaboration", "templates"], category: "google-workspace"
        ),
        "recipe-reschedule-meeting": SkillTags(
            apps: ["Calendar"], urls: ["calendar.google.com"],
            keywords: ["reschedule", "move meeting", "change time"],
            workflowTags: ["calendar", "scheduling"], category: "google-workspace"
        ),
        "recipe-review-meet-participants": SkillTags(
            apps: [], urls: ["meet.google.com"],
            keywords: ["participants", "attendees", "who's in meeting"],
            workflowTags: ["meetings"], category: "google-workspace"
        ),
        "recipe-review-overdue-tasks": SkillTags(
            apps: [], urls: ["tasks.google.com"],
            keywords: ["overdue", "overdue tasks", "missed deadlines"],
            workflowTags: ["task-management", "productivity"], category: "google-workspace"
        ),
        "recipe-save-email-attachments": SkillTags(
            apps: [], urls: ["mail.google.com"],
            keywords: ["save attachments", "email attachments", "download attachments"],
            workflowTags: ["email", "file-management"], category: "google-workspace"
        ),
        "recipe-save-email-to-doc": SkillTags(
            apps: [], urls: ["mail.google.com", "docs.google.com"],
            keywords: ["save email", "email to doc", "archive email"],
            workflowTags: ["email", "content-creation"], category: "google-workspace"
        ),
        "recipe-schedule-recurring-event": SkillTags(
            apps: ["Calendar"], urls: ["calendar.google.com"],
            keywords: ["recurring event", "repeat event", "weekly meeting"],
            workflowTags: ["calendar", "scheduling"], category: "google-workspace"
        ),
        "recipe-send-team-announcement": SkillTags(
            apps: [], urls: [],
            keywords: ["announcement", "team announcement", "notify all"],
            workflowTags: ["communication", "team-collaboration"], category: "google-workspace"
        ),
        "recipe-share-doc-and-notify": SkillTags(
            apps: [], urls: ["docs.google.com"],
            keywords: ["share doc", "share and notify", "send doc link"],
            workflowTags: ["collaboration", "communication"], category: "google-workspace"
        ),
        "recipe-share-event-materials": SkillTags(
            apps: [], urls: ["calendar.google.com", "drive.google.com"],
            keywords: ["event materials", "meeting files", "share agenda"],
            workflowTags: ["meetings", "file-management"], category: "google-workspace"
        ),
        "recipe-share-folder-with-team": SkillTags(
            apps: [], urls: ["drive.google.com"],
            keywords: ["share folder", "team folder", "folder access"],
            workflowTags: ["file-management", "collaboration"], category: "google-workspace"
        ),
        "recipe-sync-contacts-to-sheet": SkillTags(
            apps: [], urls: ["contacts.google.com", "sheets.google.com"],
            keywords: ["sync contacts", "contacts to sheet", "export contacts"],
            workflowTags: ["data-processing", "personal"], category: "google-workspace"
        ),
        "recipe-watch-drive-changes": SkillTags(
            apps: [], urls: ["drive.google.com"],
            keywords: ["watch drive", "drive changes", "file updates"],
            workflowTags: ["monitoring", "automation"], category: "google-workspace"
        ),

        // ── Personas ─────────────────────────────────────────────────────

        "persona-content-creator": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["docs.google.com", "drive.google.com"],
            keywords: ["content creator", "create content", "publish", "social media content"],
            workflowTags: ["content-creation", "social-media"], category: "persona"
        ),
        "persona-customer-support": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["mail.google.com"],
            keywords: ["customer support", "ticket", "help desk", "customer issue"],
            workflowTags: ["communication", "support"], category: "persona"
        ),
        "persona-event-coordinator": SkillTags(
            apps: ["Calendar"],
            urls: ["calendar.google.com"],
            keywords: ["event planning", "coordinate event", "venue", "logistics"],
            workflowTags: ["events", "scheduling"], category: "persona"
        ),
        "persona-exec-assistant": SkillTags(
            apps: ["Calendar", "Mail", "Safari"],
            urls: ["calendar.google.com", "mail.google.com"],
            keywords: ["executive assistant", "schedule", "inbox", "briefing", "daily brief"],
            workflowTags: ["productivity", "scheduling", "email"], category: "persona"
        ),
        "persona-hr-coordinator": SkillTags(
            apps: [],
            urls: ["docs.google.com"],
            keywords: ["onboarding", "hr", "new hire", "employee", "announcement"],
            workflowTags: ["hr", "communication"], category: "persona"
        ),
        "persona-it-admin": SkillTags(
            apps: [],
            urls: ["admin.google.com"],
            keywords: ["it admin", "security", "workspace admin", "audit"],
            workflowTags: ["admin", "security"], category: "persona"
        ),
        "persona-project-manager": SkillTags(
            apps: [],
            urls: ["docs.google.com", "sheets.google.com"],
            keywords: ["project manager", "track tasks", "milestone", "sprint", "standup"],
            workflowTags: ["project-management", "task-management"], category: "persona"
        ),
        "persona-researcher": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["scholar.google.com"],
            keywords: ["researcher", "literature", "references", "papers", "notes"],
            workflowTags: ["research", "notes"], category: "persona"
        ),
        "persona-sales-ops": SkillTags(
            apps: [],
            urls: ["sheets.google.com"],
            keywords: ["sales", "pipeline", "deals", "crm", "quota"],
            workflowTags: ["sales", "data-processing"], category: "persona"
        ),
        "persona-team-lead": SkillTags(
            apps: ["Slack"],
            urls: ["slack.com"],
            keywords: ["team lead", "standup", "coordinate", "1-on-1", "retrospective"],
            workflowTags: ["team-collaboration", "meetings"], category: "persona"
        ),

        // ── Media & Creative ─────────────────────────────────────────────

        "video-frames": SkillTags(
            apps: ["QuickTime Player", "IINA", "VLC"],
            urls: [],
            keywords: ["extract frame", "video frame", "thumbnail", "screenshot video"],
            workflowTags: ["video-production", "media-processing"],
            category: "media"
        ),

        "openai-image-gen": SkillTags(
            apps: [],
            urls: [],
            keywords: ["generate image", "ai image", "dall-e", "image generation", "create image"],
            workflowTags: ["content-creation", "ai-processing", "design"],
            category: "media"
        ),

        "nano-banana-pro": SkillTags(
            apps: [],
            urls: [],
            keywords: ["generate image", "edit image", "gemini image", "ai image"],
            workflowTags: ["content-creation", "ai-processing", "design"],
            category: "media"
        ),

        "openai-whisper": SkillTags(
            apps: [],
            urls: [],
            keywords: ["transcribe", "speech to text", "whisper", "audio to text"],
            workflowTags: ["transcription", "audio-processing"],
            category: "media"
        ),

        "openai-whisper-api": SkillTags(
            apps: [],
            urls: [],
            keywords: ["transcribe", "speech to text", "whisper api"],
            workflowTags: ["transcription", "audio-processing"],
            category: "media"
        ),

        "gifgrep": SkillTags(
            apps: [],
            urls: ["giphy.com", "tenor.com"],
            keywords: ["gif", "find gif", "search gif", "meme"],
            workflowTags: ["content-creation", "social-media"],
            category: "media"
        ),

        "songsee": SkillTags(
            apps: [],
            urls: [],
            keywords: ["spectrogram", "audio visualization", "waveform"],
            workflowTags: ["audio-processing", "analytics"],
            category: "media"
        ),

        "nano-pdf": SkillTags(
            apps: ["Preview"],
            urls: [],
            keywords: ["pdf", "edit pdf", "pdf convert", "merge pdf"],
            workflowTags: ["document-processing", "productivity"],
            category: "media"
        ),

        "canvas": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["canva.com"],
            keywords: ["canva", "design", "graphic", "poster", "social media graphic"],
            workflowTags: ["design", "content-creation"],
            category: "media"
        ),

        "camsnap": SkillTags(
            apps: [],
            urls: [],
            keywords: ["camera", "capture", "rtsp", "security camera"],
            workflowTags: ["monitoring", "hardware"],
            category: "media"
        ),

        // ── AI & Processing ──────────────────────────────────────────────

        "gemini": SkillTags(
            apps: [],
            urls: ["gemini.google.com"],
            keywords: ["gemini", "ask gemini", "google ai"],
            workflowTags: ["ai-processing", "research"],
            category: "ai"
        ),

        "sherpa-onnx-tts": SkillTags(
            apps: [],
            urls: [],
            keywords: ["text to speech", "tts", "speak", "voice", "narrate"],
            workflowTags: ["audio-processing", "accessibility"],
            category: "ai"
        ),

        "sag": SkillTags(
            apps: [],
            urls: [],
            keywords: ["text to speech", "tts", "eleven labs", "voice"],
            workflowTags: ["audio-processing", "content-creation"],
            category: "ai"
        ),

        // ── Task Management & Productivity ───────────────────────────────

        "trello": SkillTags(
            apps: ["Safari", "Chrome"],
            urls: ["trello.com"],
            keywords: ["trello", "board", "card", "kanban", "move card"],
            workflowTags: ["project-management", "task-management"],
            category: "productivity"
        ),

        "session-logs": SkillTags(
            apps: [],
            urls: [],
            keywords: ["session logs", "history", "past conversations", "search logs"],
            workflowTags: ["productivity", "analytics"],
            category: "system"
        ),

        "model-usage": SkillTags(
            apps: [],
            urls: [],
            keywords: ["model usage", "cost", "api usage", "tokens", "spending"],
            workflowTags: ["analytics", "monitoring"],
            category: "system"
        ),

        "healthcheck": SkillTags(
            apps: [],
            urls: [],
            keywords: ["security", "hardening", "audit", "firewall", "ssh"],
            workflowTags: ["security", "system-admin"],
            category: "system"
        ),

        // ── Smart Home & IoT ─────────────────────────────────────────────

        "openhue": SkillTags(
            apps: [],
            urls: [],
            keywords: ["lights", "hue", "philips hue", "smart light", "scene", "dim"],
            workflowTags: ["smart-home", "automation"],
            category: "smart-home"
        ),

        "eightctl": SkillTags(
            apps: [],
            urls: [],
            keywords: ["eight sleep", "bed temperature", "sleep", "mattress"],
            workflowTags: ["smart-home", "health"],
            category: "smart-home"
        ),

        "sonoscli": SkillTags(
            apps: [],
            urls: [],
            keywords: ["sonos", "speaker", "play music", "volume"],
            workflowTags: ["smart-home", "audio-processing"],
            category: "smart-home"
        ),

        "blucli": SkillTags(
            apps: [],
            urls: [],
            keywords: ["bluos", "speaker", "play music", "bluetooth speaker"],
            workflowTags: ["smart-home", "audio-processing"],
            category: "smart-home"
        ),

        // ── Music & Entertainment ────────────────────────────────────────

        "spotify-player": SkillTags(
            apps: ["Spotify"],
            urls: ["open.spotify.com", "spotify.com"],
            keywords: ["spotify", "play", "music", "song", "playlist", "album"],
            workflowTags: ["entertainment", "audio-processing"],
            category: "entertainment"
        ),

        // ── Location & Places ────────────────────────────────────────────

        "weather": SkillTags(
            apps: ["Weather"],
            urls: [],
            keywords: ["weather", "temperature", "forecast", "rain", "humidity"],
            workflowTags: ["information", "personal"],
            category: "information"
        ),

        "goplaces": SkillTags(
            apps: ["Maps", "Safari", "Chrome"],
            urls: ["maps.google.com"],
            keywords: ["place", "restaurant", "hotel", "cafe", "near me", "reviews"],
            workflowTags: ["information", "personal", "travel"],
            category: "information"
        ),

        "ordercli": SkillTags(
            apps: [],
            urls: ["foodora.com"],
            keywords: ["order", "food order", "delivery", "foodora"],
            workflowTags: ["personal", "shopping"],
            category: "information"
        ),

        // ── Security & Auth ──────────────────────────────────────────────

        "1password": SkillTags(
            apps: ["1Password"],
            urls: [],
            keywords: ["password", "1password", "credentials", "secret", "vault"],
            workflowTags: ["security", "personal"],
            category: "security"
        ),

        // ── System & Shell ───────────────────────────────────────────────

        "tmux": SkillTags(
            apps: ["Terminal", "iTerm2"],
            urls: [],
            keywords: ["tmux", "terminal", "session", "split"],
            workflowTags: ["development", "productivity"],
            category: "system"
        ),

        "peekaboo": SkillTags(
            apps: [],
            urls: [],
            keywords: ["screen", "ui automation", "accessibility", "ocr"],
            workflowTags: ["automation", "system"],
            category: "system"
        ),

        // ── Creative / Design Studio ──────────────────────────────────────

        "design-to-image": SkillTags(
            apps: ["Figma", "Canva", "Keynote", "Preview"],
            urls: ["figma.com", "canva.com", "dribbble.com", "behance.net"],
            keywords: ["design", "graphic design", "create image", "event invite", "social post", "banner", "thumbnail", "story card", "poster", "flyer", "render image", "remotion"],
            workflowTags: ["graphic-design", "creative", "content-creation", "visual-design"],
            category: "creative"
        ),

        "unsplash": SkillTags(
            apps: ["Safari", "Chrome", "Arc", "Figma", "Canva"],
            urls: ["unsplash.com", "pexels.com"],
            keywords: ["stock photo", "free photo", "background image", "royalty free", "stock image", "download photo", "unsplash"],
            workflowTags: ["asset-sourcing", "creative", "graphic-design"],
            category: "creative"
        ),

        "google-fonts": SkillTags(
            apps: ["Figma", "Canva", "Keynote"],
            urls: ["fonts.google.com"],
            keywords: ["font", "typography", "download font", "google fonts", "heading font", "body font"],
            workflowTags: ["asset-sourcing", "creative", "graphic-design", "typography"],
            category: "creative"
        ),

        "iconify": SkillTags(
            apps: ["Figma", "VS Code", "Cursor", "Xcode"],
            urls: ["iconify.design", "lucide.dev", "heroicons.com", "phosphoricons.com"],
            keywords: ["icon", "icons", "svg icon", "lucide", "heroicons", "phosphor", "material icons", "download icon"],
            workflowTags: ["asset-sourcing", "creative", "graphic-design", "ui-design"],
            category: "creative"
        ),

        "image2ai": SkillTags(
            apps: ["Preview", "Photos", "Figma", "Safari"],
            urls: ["dribbble.com", "behance.net", "pinterest.com"],
            keywords: ["analyze image", "reference image", "extract colors", "color palette", "design analysis", "image analysis", "style extraction"],
            workflowTags: ["analysis", "creative", "graphic-design", "reference-analysis"],
            category: "analysis"
        ),
    ]
}
