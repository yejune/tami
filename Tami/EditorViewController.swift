import Cocoa
import Highlighter

final class EditorViewController: NSViewController, NSMenuItemValidation {

    private let scrollView = NSScrollView()
    private var highlighter: Highlighter?
    private let textView = NSTextView()
    private let imageView = NSImageView()
    private let imageContainerView = NSView()
    private(set) var currentPath: String = ""
    private var imageAspectConstraint: NSLayoutConstraint?

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupHighlighter()
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

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func openFile(at url: URL) {
        currentPath = url.path
        guard let data = try? Data(contentsOf: url) else {
            showMessage("Unable to read file: \(url.lastPathComponent)")
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
