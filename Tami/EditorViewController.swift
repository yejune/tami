import Cocoa
import Highlighter
import Markdown
import PDFKit
import WebKit

final class EditorTextView: NSTextView {
    var contextMenuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?() ?? super.menu(for: event)
    }
}

final class EditorViewController: NSViewController, NSMenuItemValidation {

    static let markdownPreviewNotification = Notification.Name("EditorMarkdownPreviewRequested")
    static let htmlPreviewNotification = Notification.Name("EditorHTMLPreviewRequested")

    enum PreviewRequest {
        case markdown
        case html
    }

    private static var pendingPreviewRequests: [String: PreviewRequest] = [:]

    static func requestPreview(for url: URL, mode: PreviewRequest) {
        pendingPreviewRequests[url.path] = mode
    }

    private let scrollView = NSScrollView()
    private var highlighter: Highlighter?
    private let textView = EditorTextView()
    private let webView = WKWebView()
    private let pdfView = PDFView()
    private let imageView = NSImageView()
    private let imageContainerView = NSView()
    private(set) var currentPath: String = ""
    private enum PreviewMode {
        case none
        case markdown
        case html
    }

    private var previewMode: PreviewMode = .none
    private var pendingPreviewMode: PreviewMode = .none
    private var editorContextMenu: NSMenu?
    private var imageAspectConstraint: NSLayoutConstraint?

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupHighlighter()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMarkdownPreviewNotification(_:)),
            name: Self.markdownPreviewNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHTMLPreviewNotification(_:)),
            name: Self.htmlPreviewNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupHighlighter() {
        highlighter = Highlighter()
        highlighter?.setTheme("atom-one-dark")
    }

    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .black
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.masksToBounds = true
        scrollView.layer?.shadowColor = NSColor.black.cgColor
        scrollView.layer?.shadowOpacity = 0.8
        scrollView.layer?.shadowRadius = 12
        scrollView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.autoresizingMask = [.width]
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.insertionPointColor = .white
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainerInset = NSSize(width: 8, height: 8)

        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .none

        imageContainerView.translatesAutoresizingMaskIntoConstraints = true
        imageContainerView.autoresizingMask = [.width, .height]
        imageContainerView.addSubview(imageView)

        scrollView.documentView = textView
        view.addSubview(scrollView)
        setupMarkdownPreview()
        setupPDFView()

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func openFile(at url: URL) {
        currentPath = url.path
        previewMode = .none
        pendingPreviewMode = .none
        webView.isHidden = true
        pdfView.isHidden = true
        scrollView.isHidden = false

        if let request = Self.pendingPreviewRequests.removeValue(forKey: url.path) {
            switch request {
            case .markdown:
                pendingPreviewMode = .markdown
            case .html:
                pendingPreviewMode = .html
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            showMessage("Unable to read file: \(url.lastPathComponent)")
            return
        }

        if url.pathExtension.lowercased() == "pdf" {
            showPDF(at: url)
            return
        }

        if let image = NSImage(data: data) {
            showImage(image)
            return
        }

        if isBinaryData(data) {
            showBinaryMessage(for: url, byteCount: data.count)
            return
        }

        if let contents = String(data: data, encoding: .utf8) {
            showText(contents)
        } else if let contents = String(data: data, encoding: .macOSRoman) {
            showText(contents)
        } else {
            showMessage("Unable to decode file: \(url.lastPathComponent)")
        }
    }

    private func showText(_ contents: String) {
        textView.string = contents
        scrollView.documentView = textView

        // Apply syntax highlighting
        if let highlighted = highlighter?.highlight(contents, as: languageForCurrentFile()) {
            textView.textStorage?.setAttributedString(highlighted)
        }

        applyPendingPreviewIfNeeded()
    }

    private func setupMarkdownPreview() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isHidden = true
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(exitMarkdownPreview))
        doubleClick.numberOfClicksRequired = 2
        webView.addGestureRecognizer(doubleClick)

        let previewMenu = NSMenu()
        let markdownItem = NSMenuItem(title: "Preview Markdown", action: #selector(showMarkdownPreview), keyEquivalent: "")
        markdownItem.target = self
        previewMenu.addItem(markdownItem)
        let htmlItem = NSMenuItem(title: "Preview HTML", action: #selector(showHTMLPreview), keyEquivalent: "")
        htmlItem.target = self
        previewMenu.addItem(htmlItem)
        previewMenu.addItem(NSMenuItem.separator())
        previewMenu.addItem(withTitle: "Cut", action: #selector(cut(_:)), keyEquivalent: "")
        previewMenu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        previewMenu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        previewMenu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        editorContextMenu = previewMenu
        textView.contextMenuProvider = { [weak self] in
            guard let self else { return nil }
            return self.editorContextMenu
        }
        textView.menu = previewMenu
        scrollView.menu = previewMenu
    }

    private func setupPDFView() {
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.isHidden = true
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .white
        view.addSubview(pdfView)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func showPDF(at url: URL) {
        let document = PDFDocument(url: url)
        pdfView.document = document
        pdfView.isHidden = false
        scrollView.isHidden = true
        webView.isHidden = true
    }

    @objc private func showMarkdownPreview() {
        guard isMarkdownFile() else { return }
        let html = renderMarkdownHTML(textView.string)
        webView.loadHTMLString(html, baseURL: nil)
        previewMode = .markdown
        webView.isHidden = false
        scrollView.isHidden = true
    }

    @objc private func showHTMLPreview() {
        guard isHTMLFile() else { return }
        let baseURL = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
        webView.loadHTMLString(textView.string, baseURL: baseURL)
        previewMode = .html
        webView.isHidden = false
        scrollView.isHidden = true
    }

    @objc private func handleMarkdownPreviewNotification(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        guard url.path == currentPath else { return }
        showMarkdownPreview()
    }

    @objc private func handleHTMLPreviewNotification(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        guard url.path == currentPath else { return }
        showHTMLPreview()
    }

    @objc private func exitMarkdownPreview() {
        guard previewMode != .none else { return }
        previewMode = .none
        webView.isHidden = true
        scrollView.isHidden = false
        view.window?.makeFirstResponder(textView)
    }

    private func applyPendingPreviewIfNeeded() {
        switch pendingPreviewMode {
        case .markdown:
            pendingPreviewMode = .none
            showMarkdownPreview()
        case .html:
            pendingPreviewMode = .none
            showHTMLPreview()
        case .none:
            break
        }
    }

    private func isMarkdownFile() -> Bool {
        let ext = (currentPath as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    private func isHTMLFile() -> Bool {
        let ext = (currentPath as NSString).pathExtension.lowercased()
        return ext == "html" || ext == "htm"
    }
    private func renderMarkdownHTML(_ markdown: String) -> String {
        let baseHTML = markdownToHTML(markdown)
        let css = githubMarkdownCSS()
        if baseHTML.contains("</head>") {
            return baseHTML.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>\(css)</style>
        </head>
        <body>
        <article class="markdown-body">
        \(baseHTML)
        </article>
        </body>
        </html>
        """
    }

    private func markdownToHTML(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        return HTMLFormatter.format(document)
    }

    private func githubMarkdownCSS() -> String {
        """
        :root { color-scheme: light; }
        body { margin: 0; padding: 24px; background: #ffffff; color: #1f2328; font: 14px/1.6 -apple-system, BlinkMacSystemFont, \"Segoe UI\", Helvetica, Arial, sans-serif; }
        .markdown-body { box-sizing: border-box; min-width: 200px; max-width: 980px; margin: 0 auto; }
        .markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 { margin: 24px 0 16px; font-weight: 600; line-height: 1.25; }
        .markdown-body h1 { font-size: 2em; border-bottom: 1px solid #d8dee4; padding-bottom: .3em; }
        .markdown-body h2 { font-size: 1.5em; border-bottom: 1px solid #d8dee4; padding-bottom: .3em; }
        .markdown-body h3 { font-size: 1.25em; }
        .markdown-body h4 { font-size: 1em; }
        .markdown-body p, .markdown-body ul, .markdown-body ol, .markdown-body pre, .markdown-body blockquote, .markdown-body table { margin: 0 0 16px; }
        .markdown-body ul, .markdown-body ol { padding-left: 2em; }
        .markdown-body code, .markdown-body pre { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, \"Liberation Mono\", monospace; }
        .markdown-body code { background: rgba(27,31,35,0.05); padding: .2em .4em; border-radius: 6px; }
        .markdown-body pre { background: #f6f8fa; padding: 16px; border-radius: 6px; overflow: auto; }
        .markdown-body pre code { background: transparent; padding: 0; }
        .markdown-body blockquote { border-left: 4px solid #d0d7de; padding: 0 1em; color: #57606a; }
        .markdown-body table { border-collapse: collapse; width: 100%; }
        .markdown-body th, .markdown-body td { border: 1px solid #d0d7de; padding: 6px 13px; }
        .markdown-body tr:nth-child(2n) { background-color: #f6f8fa; }
        .markdown-body a { color: #0969da; text-decoration: none; }
        .markdown-body a:hover { text-decoration: underline; }
        .markdown-body hr { border: 0; border-top: 1px solid #d0d7de; margin: 24px 0; }
        """
    }

    private func languageForCurrentFile() -> String? {
        let ext = (currentPath as NSString).pathExtension.lowercased()
        let languageMap: [String: String] = [
            "swift": "swift",
            "js": "javascript",
            "javascript": "javascript",
            "ts": "typescript",
            "typescript": "typescript",
            "py": "python",
            "python": "python",
            "php": "php",
            "html": "html",
            "css": "css",
            "json": "json",
            "xml": "xml",
            "yaml": "yaml",
            "yml": "yaml",
            "sh": "bash",
            "bash": "bash",
            "zsh": "bash",
            "java": "java",
            "kt": "kotlin",
            "kotlin": "kotlin",
            "rs": "rust",
            "rust": "rust",
            "go": "go",
            "c": "c",
            "cpp": "cpp",
            "cc": "cpp",
            "cxx": "cpp",
            "h": "c",
            "hpp": "cpp",
            "cs": "csharp",
            "ruby": "ruby",
            "rb": "ruby"
        ]
        return languageMap[ext]
    }

    private func showImage(_ image: NSImage) {
        let isPDF = (currentPath as NSString).pathExtension.lowercased() == "pdf"
        imageView.image = image
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainerView.frame = scrollView.contentView.bounds
        imageContainerView.wantsLayer = true
        imageContainerView.layer?.backgroundColor = (isPDF ? NSColor.white : NSColor.clear).cgColor
        scrollView.documentView = imageContainerView

        NSLayoutConstraint.deactivate(imageContainerView.constraints)
        if let imageAspectConstraint {
            imageAspectConstraint.isActive = false
        }

        let aspectRatio = image.size.height > 0 ? image.size.width / image.size.height : 1
        imageAspectConstraint = imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: aspectRatio)
        imageAspectConstraint?.isActive = true

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: imageContainerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageContainerView.centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: imageContainerView.widthAnchor),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: imageContainerView.heightAnchor)
        ])
    }

    private func showMessage(_ message: String) {
        textView.string = message
        scrollView.documentView = textView
    }

    private func showBinaryMessage(for url: URL, byteCount: Int) {
        let sizeString = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        let message = [
            "Binary file preview",
            "",
            "This file can't be displayed as text.",
            "",
            "Name: \(url.lastPathComponent)",
            "Size: \(sizeString)"
        ].joined(separator: "\n")
        showMessage(message)
    }

    private func isBinaryData(_ data: Data) -> Bool {
        if data.isEmpty { return false }
        return data.contains(0)
    }

    // MARK: - Save

    func saveCurrentFile() -> Bool {
        guard !currentPath.isEmpty else {
            showAlert("No file", message: "No file is currently open.")
            return false
        }

        let contents = textView.string

        do {
            try contents.write(toFile: currentPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            showAlert("Save Failed", message: error.localizedDescription)
            return false
        }
    }

    private func showAlert(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Edit Actions

    @IBAction func cut(_ sender: Any?) {
        textView.cut(sender)
    }

    @IBAction func copy(_ sender: Any?) {
        textView.copy(sender)
    }

    @IBAction func paste(_ sender: Any?) {
        textView.paste(sender)
    }

    override func selectAll(_ sender: Any?) {
        textView.selectAll(sender)
    }

    @IBAction func undo(_ sender: Any?) {
        textView.undoManager?.undo()
    }

    @IBAction func redo(_ sender: Any?) {
        textView.undoManager?.redo()
    }

    // MARK: - Menu Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showMarkdownPreview):
            return isMarkdownFile() && previewMode == .none
        case #selector(showHTMLPreview):
            return isHTMLFile() && previewMode == .none
        case #selector(cut(_:)):
            return textView.selectedRange.length > 0
        case #selector(copy(_:)):
            return textView.selectedRange.length > 0
        case #selector(paste(_:)):
            return NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil)
        case #selector(undo(_:)):
            return textView.undoManager?.canUndo ?? false
        case #selector(redo(_:)):
            return textView.undoManager?.canRedo ?? false
        case #selector(selectAll(_:)):
            return scrollView.documentView === textView
        case #selector(performTextFinderAction(_:)):
            return scrollView.documentView === textView
        default:
            return true
        }
    }
}
