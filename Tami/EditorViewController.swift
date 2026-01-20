import Cocoa

final class EditorViewController: NSViewController {

    private let scrollView = NSScrollView()
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
    }

    private func showImage(_ image: NSImage) {
        imageView.image = image
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainerView.frame = scrollView.contentView.bounds
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
}
