import Foundation

// MARK: - CapabilityCatalog
//
// Curated registry of capabilities sourced from GitHub projects.
// Each entry represents a real tool the user can activate with one click.
// Activation: checks if binary exists → installs if needed → creates SKILL.md → creates Capability.
//
// These are modular, standalone tools — not integrated into AutoClawd's code.
// AutoClawd's job is to detect when these would be useful (OCR, transcript, URL patterns)
// and suggest/execute them at the right moment.

// MARK: - Catalog Entry

struct CatalogEntry: Identifiable {
    let id: String                              // slug
    let name: String
    let description: String
    let emoji: String
    let category: CatalogCategory
    let github: String                          // "owner/repo"
    let install: InstallMethod
    let binary: String?                         // binary name to check if already installed
    let triggerApps: [String]                   // apps that trigger this capability
    let triggerURLs: [String]                   // URL patterns
    let triggerKeywords: [String]               // voice/OCR keywords
    let skillTemplate: String                   // SKILL.md content template
    let workflowTags: [String]                  // for WorkflowBuilder matching

    var githubURL: String { "https://github.com/\(github)" }
    var isInstalled: Bool {
        guard let bin = binary else { return false }
        return Skill.commandExists(bin)
    }

    var hasSkillMD: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".autoclawd/openclaw-skills/\(id)/SKILL.md")
        return FileManager.default.fileExists(atPath: path.path)
    }
}

// MARK: - Install Method

enum InstallMethod {
    case brew(String)                           // brew install <formula>
    case brewTap(tap: String, formula: String)  // brew tap X && brew install Y
    case pip(String)                            // pip install <package>
    case npm(String)                            // npm install -g <package>
    case go(String)                             // go install <module>
    case cargo(String)                          // cargo install <crate>
    case manual(String)                         // instructions text
    case builtIn                                // uses macOS built-in tools (sips, say, etc)

    var command: String? {
        switch self {
        case .brew(let f):      return "brew install \(f)"
        case .brewTap(let t, let f): return "brew tap \(t) && brew install \(f)"
        case .pip(let p):       return "pip3 install \(p)"
        case .npm(let p):       return "npm install -g \(p)"
        case .go(let m):        return "go install \(m)"
        case .cargo(let c):     return "cargo install \(c)"
        case .manual:           return nil
        case .builtIn:          return nil
        }
    }

    var label: String {
        switch self {
        case .brew:     return "Homebrew"
        case .brewTap:  return "Homebrew"
        case .pip:      return "pip"
        case .npm:      return "npm"
        case .go:       return "Go"
        case .cargo:    return "Cargo"
        case .manual:   return "Manual"
        case .builtIn:  return "Built-in"
        }
    }
}

// MARK: - Catalog Category

enum CatalogCategory: String, CaseIterable {
    case videoAudio       = "Video & Audio"
    case imageMedia       = "Image & Media"
    case contentPublish   = "Content & Publishing"
    case communication    = "Communication"
    case storageFiles     = "Storage & Files"
    case codeDev          = "Code & Dev"
    case dataResearch     = "Data & Research"
    case aiProcessing     = "AI & Processing"
    case productivity     = "Productivity"
    case systemUtils      = "System Utilities"

    var icon: String {
        switch self {
        case .videoAudio:     return "play.rectangle.fill"
        case .imageMedia:     return "photo.fill"
        case .contentPublish: return "doc.richtext.fill"
        case .communication:  return "bubble.left.and.bubble.right.fill"
        case .storageFiles:   return "folder.fill"
        case .codeDev:        return "terminal.fill"
        case .dataResearch:   return "magnifyingglass"
        case .aiProcessing:   return "brain"
        case .productivity:   return "checklist"
        case .systemUtils:    return "gearshape.fill"
        }
    }

    var color: String {
        switch self {
        case .videoAudio:     return "red"
        case .imageMedia:     return "pink"
        case .contentPublish: return "orange"
        case .communication:  return "green"
        case .storageFiles:   return "blue"
        case .codeDev:        return "purple"
        case .dataResearch:   return "cyan"
        case .aiProcessing:   return "indigo"
        case .productivity:   return "yellow"
        case .systemUtils:    return "gray"
        }
    }
}

// MARK: - The Catalog

struct CapabilityCatalog {

    static let all: [CatalogEntry] = [

        // ── Video & Audio ──────────────────────────────────────────────────

        CatalogEntry(
            id: "yt-dlp", name: "yt-dlp", description: "Download videos from YouTube, Twitter, TikTok, and 1000+ sites",
            emoji: "\u{1F4E5}", category: .videoAudio, github: "yt-dlp/yt-dlp",
            install: .brew("yt-dlp"), binary: "yt-dlp",
            triggerApps: ["Safari", "Chrome", "Arc", "Firefox"],
            triggerURLs: ["youtube.com", "youtu.be", "tiktok.com", "twitter.com", "x.com", "vimeo.com"],
            triggerKeywords: ["download video", "save video", "grab video"],
            skillTemplate: "Download videos from URLs using yt-dlp.\n\nUsage: `yt-dlp [URL]`\nFormats: `yt-dlp -f best [URL]`\nAudio only: `yt-dlp -x --audio-format mp3 [URL]`",
            workflowTags: ["video-production", "content-creation", "media-download"]
        ),

        CatalogEntry(
            id: "ffmpeg", name: "FFmpeg", description: "Universal video/audio converter, trimmer, merger, and processor",
            emoji: "\u{1F3AC}", category: .videoAudio, github: "FFmpeg/FFmpeg",
            install: .brew("ffmpeg"), binary: "ffmpeg",
            triggerApps: ["QuickTime Player", "IINA", "VLC"],
            triggerURLs: [],
            triggerKeywords: ["convert video", "trim video", "merge video", "compress video", "extract audio"],
            skillTemplate: "Process video/audio with ffmpeg.\n\nConvert: `ffmpeg -i input.mp4 output.webm`\nTrim: `ffmpeg -i input.mp4 -ss 00:01:00 -to 00:02:00 output.mp4`\nExtract audio: `ffmpeg -i input.mp4 -vn output.mp3`\nCompress: `ffmpeg -i input.mp4 -crf 28 output.mp4`",
            workflowTags: ["video-production", "audio-processing", "media-conversion"]
        ),

        CatalogEntry(
            id: "whisper-cpp", name: "Whisper.cpp", description: "Fast local speech-to-text transcription using OpenAI Whisper models",
            emoji: "\u{1F399}\u{FE0F}", category: .videoAudio, github: "ggerganov/whisper.cpp",
            install: .brew("whisper-cpp"), binary: "whisper-cpp",
            triggerApps: [],
            triggerURLs: [],
            triggerKeywords: ["transcribe audio", "transcribe video", "speech to text", "transcription"],
            skillTemplate: "Transcribe audio/video locally with Whisper.cpp.\n\nUsage: `whisper-cpp -m models/ggml-base.en.bin -f input.wav`\nWith timestamps: `whisper-cpp -m models/ggml-base.en.bin -f input.wav -otxt`",
            workflowTags: ["transcription", "audio-processing"]
        ),

        CatalogEntry(
            id: "sox", name: "SoX", description: "Swiss army knife of audio processing — convert, trim, apply effects",
            emoji: "\u{1F3B5}", category: .videoAudio, github: "chirlu/sox",
            install: .brew("sox"), binary: "sox",
            triggerApps: [],
            triggerURLs: [],
            triggerKeywords: ["audio convert", "audio trim", "normalize audio", "audio effects"],
            skillTemplate: "Process audio with SoX.\n\nConvert: `sox input.wav output.mp3`\nTrim: `sox input.wav output.wav trim 10 30`\nNormalize: `sox --norm input.wav output.wav`",
            workflowTags: ["audio-processing"]
        ),

        // ── Creative / Design Studio ─────────────────────────────────────

        CatalogEntry(
            id: "design-to-image", name: "Design to Image", description: "Programmatic graphic design — render static images & animated videos from React/Remotion compositions",
            emoji: "🎨", category: .imageMedia, github: "remotion-dev/remotion",
            install: .npm("create-video@latest"), binary: "npx",
            triggerApps: ["Figma", "Canva", "Keynote"],
            triggerURLs: ["figma.com", "canva.com", "dribbble.com"],
            triggerKeywords: ["design", "graphic design", "create image", "event invite", "social post", "banner", "thumbnail", "render image"],
            skillTemplate: "Programmatic graphic design engine.\n\nStill: `cd ~/.autoclawd/design-studio && npx remotion still src/index.ts EventInvite --output out/invite.png --props '{\"title\":\"Hello\"}'`\nVideo: `npx remotion render src/index.ts Comp --output out/video.mp4`\nTemplates: EventInvite, SocialPost, StoryCard, Banner, Thumbnail",
            workflowTags: ["graphic-design", "creative", "content-creation", "visual-design"]
        ),

        CatalogEntry(
            id: "unsplash", name: "Unsplash", description: "Search and download royalty-free stock photos for designs and content",
            emoji: "📸", category: .imageMedia, github: "unsplash/unsplash-js",
            install: .builtIn, binary: "curl",
            triggerApps: ["Safari", "Figma", "Canva"],
            triggerURLs: ["unsplash.com", "pexels.com"],
            triggerKeywords: ["stock photo", "free photo", "background image", "royalty free", "unsplash"],
            skillTemplate: "Download royalty-free photos.\n\nQuick: `curl -L 'https://source.unsplash.com/1080x1080/?office' -o photo.jpg`\nAPI: `curl -s 'https://api.unsplash.com/search/photos?query=tech' -H 'Authorization: Client-ID KEY'`",
            workflowTags: ["asset-sourcing", "creative", "graphic-design"]
        ),

        CatalogEntry(
            id: "google-fonts", name: "Google Fonts", description: "Browse and download 1,500+ free font families for designs",
            emoji: "🔤", category: .imageMedia, github: "google/fonts",
            install: .builtIn, binary: "curl",
            triggerApps: ["Figma", "Canva", "Keynote"],
            triggerURLs: ["fonts.google.com"],
            triggerKeywords: ["font", "typography", "download font", "google fonts", "heading font"],
            skillTemplate: "Download Google Fonts.\n\nDownload: `curl -L 'https://fonts.google.com/download?family=Inter' -o font.zip && unzip font.zip`\nCSS: `curl -L 'https://fonts.googleapis.com/css2?family=Inter:wght@400;700'`",
            workflowTags: ["asset-sourcing", "creative", "graphic-design", "typography"]
        ),

        CatalogEntry(
            id: "iconify", name: "Iconify", description: "200,000+ open-source icons from 150+ sets — Lucide, Phosphor, Material, Heroicons as SVG",
            emoji: "✨", category: .imageMedia, github: "iconify/iconify",
            install: .builtIn, binary: "curl",
            triggerApps: ["Figma", "VS Code", "Cursor"],
            triggerURLs: ["iconify.design", "lucide.dev"],
            triggerKeywords: ["icon", "icons", "svg icon", "lucide", "heroicons", "phosphor", "material icons"],
            skillTemplate: "Get icons as SVG.\n\nDownload: `curl -s 'https://api.iconify.design/lucide/calendar.svg?color=%23FF6B35&width=48' -o icon.svg`\nSearch: `curl -s 'https://api.iconify.design/search?query=calendar&limit=10'`",
            workflowTags: ["asset-sourcing", "creative", "graphic-design", "ui-design"]
        ),

        CatalogEntry(
            id: "image2ai", name: "Image to AI", description: "Analyze reference images — extract colors, typography, layout, and style for design reproduction",
            emoji: "🔍", category: .imageMedia, github: "autoclawd/image2ai",
            install: .builtIn, binary: "sips",
            triggerApps: ["Preview", "Photos", "Figma"],
            triggerURLs: ["dribbble.com", "behance.net", "pinterest.com"],
            triggerKeywords: ["analyze image", "reference image", "extract colors", "color palette", "design analysis", "style extraction"],
            skillTemplate: "Analyze reference images for design reproduction.\n\nMetadata: `sips --getProperty all image.png`\nColors: `python3 -c \"from PIL import Image; ...\" # extract palette`\nUse with Claude for full style analysis → design tokens JSON",
            workflowTags: ["analysis", "creative", "graphic-design", "reference-analysis"]
        ),

        // ── Image & Media ──────────────────────────────────────────────────

        CatalogEntry(
            id: "imagemagick", name: "ImageMagick", description: "Convert, resize, crop, and transform images in any format",
            emoji: "\u{1F5BC}\u{FE0F}", category: .imageMedia, github: "ImageMagick/ImageMagick",
            install: .brew("imagemagick"), binary: "magick",
            triggerApps: ["Preview", "Photos"],
            triggerURLs: [],
            triggerKeywords: ["convert image", "resize image", "crop image", "compress image", "png to jpg", "jpg to png", "webp"],
            skillTemplate: "Process images with ImageMagick.\n\nConvert: `magick input.png output.jpg`\nResize: `magick input.png -resize 800x600 output.png`\nCompress: `magick input.png -quality 80 output.jpg`\nBatch: `magick mogrify -resize 50% *.png`",
            workflowTags: ["image-processing", "media-conversion"]
        ),

        CatalogEntry(
            id: "sips-convert", name: "sips (Built-in)", description: "macOS built-in image converter — PNG, JPG, HEIC, WebP, TIFF, no install needed",
            emoji: "\u{1F4F7}", category: .imageMedia, github: "apple/darwin-xnu",
            install: .builtIn, binary: "sips",
            triggerApps: ["Preview", "Finder"],
            triggerURLs: [],
            triggerKeywords: ["convert image", "png to jpg", "heic to jpg", "image format", "resize photo"],
            skillTemplate: "Convert images with macOS built-in sips.\n\nConvert format: `sips -s format jpeg input.png --out output.jpg`\nResize: `sips -Z 800 input.png --out resized.png`\nFormats: jpeg, png, tiff, gif, bmp, heic\nBatch: `for f in *.heic; do sips -s format jpeg \"$f\" --out \"${f%.heic}.jpg\"; done`",
            workflowTags: ["image-processing", "media-conversion", "productivity"]
        ),

        CatalogEntry(
            id: "optipng", name: "OptiPNG", description: "Losslessly compress PNG images — smaller files, same quality",
            emoji: "\u{1F4E6}", category: .imageMedia, github: "nickthecook/optipng",
            install: .brew("optipng"), binary: "optipng",
            triggerApps: [],
            triggerURLs: [],
            triggerKeywords: ["compress png", "optimize png", "smaller png"],
            skillTemplate: "Compress PNG files losslessly.\n\nBasic: `optipng input.png`\nMax compression: `optipng -o7 input.png`\nBatch: `optipng *.png`",
            workflowTags: ["image-processing", "optimization"]
        ),

        CatalogEntry(
            id: "svgo", name: "SVGO", description: "Optimize and clean SVG files — remove metadata, simplify paths",
            emoji: "\u{2702}\u{FE0F}", category: .imageMedia, github: "nickthecook/svgo",
            install: .npm("svgo"), binary: "svgo",
            triggerApps: ["Figma"],
            triggerURLs: ["figma.com"],
            triggerKeywords: ["optimize svg", "clean svg", "svg"],
            skillTemplate: "Optimize SVG files.\n\nBasic: `svgo input.svg -o output.svg`\nBatch: `svgo -f ./svgs -o ./optimized`",
            workflowTags: ["image-processing", "web-development"]
        ),

        // ── Content & Publishing ──────────────────────────────────────────

        CatalogEntry(
            id: "pandoc", name: "Pandoc", description: "Universal document converter — Markdown, DOCX, PDF, HTML, LaTeX, EPUB",
            emoji: "\u{1F4D1}", category: .contentPublish, github: "jgm/pandoc",
            install: .brew("pandoc"), binary: "pandoc",
            triggerApps: ["TextEdit", "Pages", "Word"],
            triggerURLs: [],
            triggerKeywords: ["convert document", "markdown to pdf", "docx to md", "epub", "latex"],
            skillTemplate: "Convert documents with Pandoc.\n\nMD to PDF: `pandoc input.md -o output.pdf`\nMD to DOCX: `pandoc input.md -o output.docx`\nHTML to MD: `pandoc input.html -o output.md`\nWith TOC: `pandoc input.md --toc -o output.pdf`",
            workflowTags: ["content-creation", "document-conversion"]
        ),

        CatalogEntry(
            id: "hugo", name: "Hugo", description: "Fastest static site generator — build blogs, docs, and portfolios",
            emoji: "\u{1F310}", category: .contentPublish, github: "gohugoio/hugo",
            install: .brew("hugo"), binary: "hugo",
            triggerApps: [],
            triggerURLs: ["gohugo.io"],
            triggerKeywords: ["build site", "static site", "blog", "hugo"],
            skillTemplate: "Build static sites with Hugo.\n\nNew site: `hugo new site mysite`\nNew post: `hugo new posts/my-post.md`\nDev server: `hugo server -D`\nBuild: `hugo --minify`",
            workflowTags: ["content-creation", "web-development"]
        ),

        CatalogEntry(
            id: "marp", name: "Marp", description: "Create beautiful slide decks from Markdown — export to PDF, PPTX, HTML",
            emoji: "\u{1F4CA}", category: .contentPublish, github: "marp-team/marp-cli",
            install: .npm("@marp-team/marp-cli"), binary: "marp",
            triggerApps: ["Keynote", "PowerPoint"],
            triggerURLs: [],
            triggerKeywords: ["create slides", "presentation", "deck", "markdown slides"],
            skillTemplate: "Create slides from Markdown.\n\nTo PDF: `marp slides.md -o slides.pdf`\nTo PPTX: `marp slides.md -o slides.pptx`\nTo HTML: `marp slides.md -o slides.html`\nWith theme: `marp --theme gaia slides.md -o slides.pdf`",
            workflowTags: ["content-creation", "presentations"]
        ),

        // ── Communication ──────────────────────────────────────────────────

        CatalogEntry(
            id: "gh-cli", name: "GitHub CLI", description: "Create issues, PRs, releases, and manage repos from the terminal",
            emoji: "\u{1F4BB}", category: .communication, github: "cli/cli",
            install: .brew("gh"), binary: "gh",
            triggerApps: ["Safari", "Chrome", "Arc"],
            triggerURLs: ["github.com"],
            triggerKeywords: ["create issue", "create pr", "pull request", "github", "release"],
            skillTemplate: "Manage GitHub from the terminal.\n\nCreate issue: `gh issue create --title 'Bug' --body 'Details'`\nCreate PR: `gh pr create --title 'Feature' --body 'Description'`\nList PRs: `gh pr list`\nClone: `gh repo clone owner/repo`",
            workflowTags: ["development", "communication", "project-management"]
        ),

        CatalogEntry(
            id: "slack-cli", name: "Slack CLI", description: "Send messages, upload files, and manage channels from the terminal",
            emoji: "\u{1F4AC}", category: .communication, github: "rockymadden/slack-cli",
            install: .brew("slack-cli"), binary: "slack",
            triggerApps: ["Slack"],
            triggerURLs: ["slack.com"],
            triggerKeywords: ["send slack", "post slack", "slack message", "notify team"],
            skillTemplate: "Send Slack messages from the terminal.\n\nSend: `slack chat send 'Hello team!' '#general'`\nUpload: `slack file upload report.pdf '#general'`\nList channels: `slack channels list`",
            workflowTags: ["communication", "team-collaboration"]
        ),

        CatalogEntry(
            id: "noti", name: "Noti", description: "Send notifications when long-running commands finish — Slack, email, macOS",
            emoji: "\u{1F514}", category: .communication, github: "variadico/noti",
            install: .brew("noti"), binary: "noti",
            triggerApps: ["Terminal", "iTerm2"],
            triggerURLs: [],
            triggerKeywords: ["notify when done", "alert when done", "notification"],
            skillTemplate: "Notify when a command finishes.\n\nmacOS: `noti make build`\nSlack: `noti -k slack make build`\nEmail: `noti -k mail make build`",
            workflowTags: ["productivity", "automation"]
        ),

        // ── Storage & Files ────────────────────────────────────────────────

        CatalogEntry(
            id: "rclone", name: "Rclone", description: "Sync files to and from Google Drive, S3, Dropbox, and 50+ cloud services",
            emoji: "\u{2601}\u{FE0F}", category: .storageFiles, github: "rclone/rclone",
            install: .brew("rclone"), binary: "rclone",
            triggerApps: [],
            triggerURLs: ["drive.google.com", "dropbox.com"],
            triggerKeywords: ["sync files", "upload drive", "cloud sync", "backup"],
            skillTemplate: "Sync files with cloud storage.\n\nSync to Drive: `rclone sync ./local remote:folder`\nCopy: `rclone copy file.pdf remote:docs/`\nList: `rclone ls remote:path`\nConfig: `rclone config`",
            workflowTags: ["file-management", "cloud-storage"]
        ),

        CatalogEntry(
            id: "fzf", name: "fzf", description: "Fuzzy file finder — instantly search files, history, processes, anything",
            emoji: "\u{1F50D}", category: .storageFiles, github: "junegunn/fzf",
            install: .brew("fzf"), binary: "fzf",
            triggerApps: ["Terminal", "iTerm2"],
            triggerURLs: [],
            triggerKeywords: ["find file", "search files", "fuzzy search"],
            skillTemplate: "Fuzzy find anything.\n\nFiles: `fzf`\nWith preview: `fzf --preview 'cat {}'`\nHistory: `history | fzf`\nPipe: `git log --oneline | fzf`",
            workflowTags: ["productivity", "file-management"]
        ),

        CatalogEntry(
            id: "trash", name: "trash-cli", description: "Move files to Trash instead of permanently deleting — safe rm replacement",
            emoji: "\u{1F5D1}\u{FE0F}", category: .storageFiles, github: "ali-rantakari/trash",
            install: .brew("trash"), binary: "trash",
            triggerApps: ["Terminal", "Finder"],
            triggerURLs: [],
            triggerKeywords: ["delete file", "remove file", "trash", "safe delete"],
            skillTemplate: "Safe file deletion (moves to Trash).\n\nDelete: `trash file.txt`\nMultiple: `trash *.log`\nAlways use `trash` instead of `rm` for reversible deletion.",
            workflowTags: ["file-management", "safety"]
        ),

        CatalogEntry(
            id: "bat", name: "bat", description: "Better cat — syntax highlighting, line numbers, git integration",
            emoji: "\u{1F987}", category: .storageFiles, github: "sharkdp/bat",
            install: .brew("bat"), binary: "bat",
            triggerApps: ["Terminal"],
            triggerURLs: [],
            triggerKeywords: ["view file", "read file", "cat with colors"],
            skillTemplate: "View files with syntax highlighting.\n\nBasic: `bat file.py`\nLine range: `bat -r 10:20 file.py`\nPlain: `bat -p file.py`\nDiff: `bat --diff file1 file2`",
            workflowTags: ["development", "productivity"]
        ),

        // ── Code & Dev ─────────────────────────────────────────────────────

        CatalogEntry(
            id: "jq", name: "jq", description: "JSON processor — query, filter, transform JSON from the command line",
            emoji: "\u{1F4CB}", category: .codeDev, github: "jqlang/jq",
            install: .brew("jq"), binary: "jq",
            triggerApps: ["Terminal"],
            triggerURLs: [],
            triggerKeywords: ["parse json", "json query", "filter json", "transform json"],
            skillTemplate: "Process JSON with jq.\n\nPretty print: `cat data.json | jq .`\nFilter: `jq '.users[] | .name' data.json`\nCount: `jq '.items | length' data.json`\nSelect: `jq '.[] | select(.status == \"active\")' data.json`",
            workflowTags: ["development", "data-processing"]
        ),

        CatalogEntry(
            id: "httpie", name: "HTTPie", description: "Human-friendly HTTP client — better curl with colors and JSON support",
            emoji: "\u{1F310}", category: .codeDev, github: "httpie/cli",
            install: .brew("httpie"), binary: "http",
            triggerApps: ["Postman"],
            triggerURLs: [],
            triggerKeywords: ["api call", "http request", "test api", "curl"],
            skillTemplate: "Make HTTP requests with HTTPie.\n\nGET: `http GET api.example.com/users`\nPOST: `http POST api.example.com/users name=John`\nHeaders: `http GET api.com/data Authorization:'Bearer TOKEN'`\nDownload: `http --download https://example.com/file.zip`",
            workflowTags: ["development", "api-testing"]
        ),

        CatalogEntry(
            id: "lazygit", name: "LazyGit", description: "Beautiful terminal UI for Git — stage, commit, branch, merge visually",
            emoji: "\u{1F333}", category: .codeDev, github: "jesseduffield/lazygit",
            install: .brew("lazygit"), binary: "lazygit",
            triggerApps: ["Terminal", "iTerm2"],
            triggerURLs: ["github.com"],
            triggerKeywords: ["git", "commit", "merge", "branch", "lazygit"],
            skillTemplate: "Visual Git interface.\n\nLaunch: `lazygit`\nIn directory: `lazygit -p /path/to/repo`",
            workflowTags: ["development", "git"]
        ),

        CatalogEntry(
            id: "tokei", name: "Tokei", description: "Count lines of code by language — fast project stats",
            emoji: "\u{1F4CA}", category: .codeDev, github: "XAMPPRocky/tokei",
            install: .brew("tokei"), binary: "tokei",
            triggerApps: [],
            triggerURLs: [],
            triggerKeywords: ["count lines", "code stats", "project stats", "lines of code"],
            skillTemplate: "Count lines of code.\n\nCurrent dir: `tokei`\nSpecific dir: `tokei /path/to/project`\nBy file: `tokei --files`",
            workflowTags: ["development", "analytics"]
        ),

        CatalogEntry(
            id: "vercel-cli", name: "Vercel CLI", description: "Deploy frontend apps instantly — preview URLs, environment management",
            emoji: "\u{25B2}", category: .codeDev, github: "vercel/vercel",
            install: .npm("vercel"), binary: "vercel",
            triggerApps: [],
            triggerURLs: ["vercel.com"],
            triggerKeywords: ["deploy", "vercel", "preview deploy", "ship"],
            skillTemplate: "Deploy with Vercel.\n\nDeploy: `vercel`\nProduction: `vercel --prod`\nEnvironment: `vercel env pull`\nLogs: `vercel logs <url>`",
            workflowTags: ["development", "deployment"]
        ),

        CatalogEntry(
            id: "railway-cli", name: "Railway CLI", description: "Deploy backend services — databases, cron jobs, and full-stack apps",
            emoji: "\u{1F682}", category: .codeDev, github: "railwayapp/cli",
            install: .brew("railway"), binary: "railway",
            triggerApps: [],
            triggerURLs: ["railway.app"],
            triggerKeywords: ["deploy backend", "railway", "database deploy"],
            skillTemplate: "Deploy with Railway.\n\nDeploy: `railway up`\nLogs: `railway logs`\nLink: `railway link`\nVariables: `railway variables`",
            workflowTags: ["development", "deployment"]
        ),

        // ── Data & Research ────────────────────────────────────────────────

        CatalogEntry(
            id: "ripgrep", name: "ripgrep", description: "Blazingly fast search through code and text files — better grep",
            emoji: "\u{26A1}", category: .dataResearch, github: "BurntSushi/ripgrep",
            install: .brew("ripgrep"), binary: "rg",
            triggerApps: ["Terminal"],
            triggerURLs: [],
            triggerKeywords: ["search code", "find in files", "grep"],
            skillTemplate: "Search files fast with ripgrep.\n\nSearch: `rg 'pattern' ./src`\nFile types: `rg -t py 'import'`\nCase insensitive: `rg -i 'error'`\nWith context: `rg -C 3 'TODO'`",
            workflowTags: ["development", "research"]
        ),

        CatalogEntry(
            id: "pup", name: "pup", description: "HTML parser for the command line — extract data from web pages with CSS selectors",
            emoji: "\u{1F3AF}", category: .dataResearch, github: "ericchiang/pup",
            install: .brew("pup"), binary: "pup",
            triggerApps: [],
            triggerURLs: [],
            triggerKeywords: ["scrape", "parse html", "extract html", "css selector"],
            skillTemplate: "Parse HTML with CSS selectors.\n\nTitles: `curl -s url | pup 'h1 text{}'`\nLinks: `curl -s url | pup 'a attr{href}'`\nImages: `curl -s url | pup 'img attr{src}'`",
            workflowTags: ["data-extraction", "research", "web-scraping"]
        ),

        CatalogEntry(
            id: "xsv", name: "xsv", description: "Fast CSV toolkit — search, join, slice, stats on large CSV files",
            emoji: "\u{1F4C4}", category: .dataResearch, github: "BurntSushi/xsv",
            install: .brew("xsv"), binary: "xsv",
            triggerApps: ["Numbers", "Excel"],
            triggerURLs: [],
            triggerKeywords: ["csv", "parse csv", "csv stats", "csv filter"],
            skillTemplate: "Process CSV files.\n\nStats: `xsv stats data.csv`\nSearch: `xsv search 'query' data.csv`\nSelect columns: `xsv select name,email data.csv`\nSort: `xsv sort -s amount data.csv`",
            workflowTags: ["data-processing", "analytics"]
        ),

        CatalogEntry(
            id: "tldr", name: "tldr", description: "Simplified man pages — practical examples for every command",
            emoji: "\u{1F4D6}", category: .dataResearch, github: "tldr-pages/tldr",
            install: .brew("tlrc"), binary: "tldr",
            triggerApps: ["Terminal"],
            triggerURLs: [],
            triggerKeywords: ["how to use", "command help", "man page", "tldr"],
            skillTemplate: "Quick command reference.\n\nLookup: `tldr tar`\nUpdate: `tldr --update`\nList: `tldr --list`",
            workflowTags: ["productivity", "reference"]
        ),

        // ── AI & Processing ────────────────────────────────────────────────

        CatalogEntry(
            id: "ollama", name: "Ollama", description: "Run LLMs locally — Llama, Mistral, Gemma, Phi, and more on your Mac",
            emoji: "\u{1F999}", category: .aiProcessing, github: "ollama/ollama",
            install: .brew("ollama"), binary: "ollama",
            triggerApps: [],
            triggerURLs: ["ollama.ai"],
            triggerKeywords: ["local ai", "run model", "ollama", "llama"],
            skillTemplate: "Run local LLMs with Ollama.\n\nChat: `ollama run llama3.2`\nPull model: `ollama pull mistral`\nList: `ollama list`\nAPI: `curl http://localhost:11434/api/generate -d '{\"model\":\"llama3.2\",\"prompt\":\"Hello\"}'`",
            workflowTags: ["ai-processing", "local-ai"]
        ),

        CatalogEntry(
            id: "fabric", name: "Fabric", description: "AI augmentation framework — summarize, analyze, extract with prompt patterns",
            emoji: "\u{1F9F5}", category: .aiProcessing, github: "danielmiessler/fabric",
            install: .go("github.com/danielmiessler/fabric@latest"), binary: "fabric",
            triggerApps: [],
            triggerURLs: [],
            triggerKeywords: ["summarize", "analyze", "extract wisdom", "fabric"],
            skillTemplate: "AI-powered analysis with Fabric patterns.\n\nSummarize: `echo 'text' | fabric -p summarize`\nExtract: `cat article.md | fabric -p extract_wisdom`\nYouTube: `fabric -y 'https://youtube.com/...' -p summarize`\nList patterns: `fabric --list`",
            workflowTags: ["ai-processing", "content-analysis"]
        ),

        CatalogEntry(
            id: "aichat", name: "AIChat", description: "Multi-model AI CLI — chat with GPT, Claude, Gemini, local models from terminal",
            emoji: "\u{1F916}", category: .aiProcessing, github: "sigoden/aichat",
            install: .brew("aichat"), binary: "aichat",
            triggerApps: ["Terminal"],
            triggerURLs: [],
            triggerKeywords: ["ai chat", "ask ai", "gpt", "claude terminal"],
            skillTemplate: "Chat with AI models from terminal.\n\nChat: `aichat 'explain this code'`\nPipe: `cat error.log | aichat 'what went wrong?'`\nExecute: `aichat -e 'list large files'`",
            workflowTags: ["ai-processing", "productivity"]
        ),

        // ── Productivity ───────────────────────────────────────────────────

        CatalogEntry(
            id: "task", name: "Taskwarrior", description: "Powerful command-line task manager with filtering, reports, and sync",
            emoji: "\u{2705}", category: .productivity, github: "GothenburgBitFactory/taskwarrior",
            install: .brew("task"), binary: "task",
            triggerApps: [],
            triggerURLs: [],
            triggerKeywords: ["add task", "task list", "todo", "taskwarrior"],
            skillTemplate: "Manage tasks from the terminal.\n\nAdd: `task add 'Buy groceries' due:tomorrow`\nList: `task list`\nDone: `task 1 done`\nPriority: `task add priority:H 'Urgent fix'`",
            workflowTags: ["productivity", "task-management"]
        ),

        CatalogEntry(
            id: "tmux", name: "tmux", description: "Terminal multiplexer — split panes, persistent sessions, remote work",
            emoji: "\u{1F5A5}\u{FE0F}", category: .productivity, github: "tmux/tmux",
            install: .brew("tmux"), binary: "tmux",
            triggerApps: ["Terminal", "iTerm2"],
            triggerURLs: [],
            triggerKeywords: ["terminal split", "tmux", "session", "multiplex"],
            skillTemplate: "Terminal multiplexer.\n\nNew session: `tmux new -s work`\nSplit horizontal: `Ctrl+b %`\nSplit vertical: `Ctrl+b \"`\nDetach: `Ctrl+b d`\nReattach: `tmux attach -t work`",
            workflowTags: ["productivity", "development"]
        ),

        CatalogEntry(
            id: "entr", name: "entr", description: "Run commands when files change — auto-reload, auto-test, auto-build",
            emoji: "\u{1F504}", category: .productivity, github: "eradman/entr",
            install: .brew("entr"), binary: "entr",
            triggerApps: [],
            triggerURLs: [],
            triggerKeywords: ["watch files", "auto reload", "file change", "auto test"],
            skillTemplate: "Run commands on file changes.\n\nReload: `ls *.py | entr python main.py`\nTest: `find . -name '*.ts' | entr npm test`\nBuild: `ls src/*.swift | entr make`\nClear+run: `ls *.go | entr -c go run .`",
            workflowTags: ["development", "automation"]
        ),

        // ── System Utilities ───────────────────────────────────────────────

        CatalogEntry(
            id: "htop", name: "htop", description: "Interactive process viewer — monitor CPU, memory, and kill processes",
            emoji: "\u{1F4DF}", category: .systemUtils, github: "htop-dev/htop",
            install: .brew("htop"), binary: "htop",
            triggerApps: ["Activity Monitor"],
            triggerURLs: [],
            triggerKeywords: ["process", "cpu usage", "memory", "kill process", "htop"],
            skillTemplate: "Monitor system processes.\n\nLaunch: `htop`\nFilter: `htop -p PID`\nSort by memory: press M\nKill process: select + F9",
            workflowTags: ["system-admin", "monitoring"]
        ),

        CatalogEntry(
            id: "dust", name: "dust", description: "Intuitive disk usage analyzer — find what's eating your storage",
            emoji: "\u{1F4BE}", category: .systemUtils, github: "bootandy/dust",
            install: .brew("dust"), binary: "dust",
            triggerApps: ["Finder"],
            triggerURLs: [],
            triggerKeywords: ["disk space", "storage", "large files", "disk usage"],
            skillTemplate: "Analyze disk usage.\n\nCurrent dir: `dust`\nSpecific dir: `dust /path`\nReverse: `dust -r`\nDepth: `dust -d 2`",
            workflowTags: ["system-admin", "file-management"]
        ),

        CatalogEntry(
            id: "dog", name: "dog", description: "Modern DNS client — query DNS records with colors and JSON output",
            emoji: "\u{1F436}", category: .systemUtils, github: "ogham/dog",
            install: .brew("dog"), binary: "dog",
            triggerApps: [],
            triggerURLs: [],
            triggerKeywords: ["dns lookup", "dns query", "domain check"],
            skillTemplate: "DNS lookups.\n\nA record: `dog example.com`\nMX: `dog example.com MX`\nJSON: `dog example.com --json`\nSpecific server: `dog example.com @1.1.1.1`",
            workflowTags: ["system-admin", "networking"]
        ),

        CatalogEntry(
            id: "hyperfine", name: "Hyperfine", description: "Command benchmarking — measure and compare execution times",
            emoji: "\u{23F1}\u{FE0F}", category: .systemUtils, github: "sharkdp/hyperfine",
            install: .brew("hyperfine"), binary: "hyperfine",
            triggerApps: ["Terminal"],
            triggerURLs: [],
            triggerKeywords: ["benchmark", "measure time", "compare speed", "performance"],
            skillTemplate: "Benchmark commands.\n\nSingle: `hyperfine 'sleep 0.3'`\nCompare: `hyperfine 'fd . -e py' 'find . -name \"*.py\"'`\nWarmup: `hyperfine --warmup 3 'command'`",
            workflowTags: ["development", "benchmarking"]
        ),
    ]

    // MARK: - Queries

    static func byCategory(_ category: CatalogCategory) -> [CatalogEntry] {
        all.filter { $0.category == category }
    }

    static func search(_ query: String) -> [CatalogEntry] {
        let q = query.lowercased()
        return all.filter {
            $0.name.lowercased().contains(q)
            || $0.description.lowercased().contains(q)
            || $0.triggerKeywords.contains(where: { $0.lowercased().contains(q) })
            || $0.category.rawValue.lowercased().contains(q)
        }
    }

    static func notActivated() -> [CatalogEntry] {
        all.filter { !$0.hasSkillMD }
    }

    static func activated() -> [CatalogEntry] {
        all.filter { $0.hasSkillMD }
    }
}
