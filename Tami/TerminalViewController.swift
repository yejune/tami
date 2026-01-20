import Cocoa

final class TerminalViewController: NSViewController, LocalProcessTerminalViewDelegate {

    private var terminalView: LocalProcessTerminalView?
    private var terminalContainer: NSView!

    private(set) var currentPath: String = ""

    private let backgroundColor = NSColor.systemRed
    private let terminalBackgroundColor = NSColor.clear

    override func loadView() {
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        effectView.material = .sidebar
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        view = effectView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = backgroundColor.cgColor

        terminalContainer = NSView()
        terminalContainer.wantsLayer = true
        terminalContainer.layer?.cornerRadius = 8
        terminalContainer.layer?.masksToBounds = true
        terminalContainer.layer?.backgroundColor = NSColor.black.cgColor
        terminalContainer.layer?.borderWidth = 0
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalContainer)

        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.processDelegate = self
        terminal.caretColor = .systemGreen
        terminal.caretTextColor = .black
        terminal.nativeForegroundColor = .systemPurple
        terminal.nativeBackgroundColor = terminalBackgroundColor
        terminal.getTerminal().setCursorStyle(.steadyBlock)
        terminalContainer.addSubview(terminal)
        terminalView = terminal

        let containerInset: CGFloat = 0
        NSLayoutConstraint.activate([
            terminalContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: containerInset),
            terminalContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: containerInset),
            terminalContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -containerInset),
            terminalContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -containerInset),

            terminal.topAnchor.constraint(equalTo: terminalContainer.topAnchor, constant: 8),
            terminal.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor, constant: 8),
            terminal.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor, constant: -8),
            terminal.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor, constant: -8)
        ])
    }

    func openTerminal(at path: String) {
        currentPath = path

        guard let terminalView else { return }

        if terminalView.process.running {
            terminalView.terminate()
        }

        let shell = getShell()
        let shellIdiom = "-" + NSString(string: shell).lastPathComponent
        terminalView.startProcess(executable: shell, args: ["--login"], execName: shellIdiom, currentDirectory: path)
        focusTerminal()
    }

    func focusTerminal() {
        terminalView?.window?.makeFirstResponder(terminalView)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // No-op: size is managed by the split view.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Optional: surface terminal title in the UI if needed.
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory) else { return }
        let path = url.path
        currentPath = path
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Keep the view alive; process can be restarted via favorites.
    }

    // MARK: - Helpers

    private func getShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            return String(cString: shell)
        }
        return "/bin/zsh"
    }
}
