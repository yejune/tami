import Cocoa

final class TerminalViewController: NSViewController, LocalProcessTerminalViewDelegate {

    private var terminalView: LocalProcessTerminalView?
    private var terminalContainer: NSView!

    private(set) var currentPath: String = ""

    private let backgroundColor = NSColor.clear
    private let terminalBackgroundColor = NSColor.black

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
        terminalContainer.layer?.cornerRadius = 10
        terminalContainer.layer?.masksToBounds = true
        terminalContainer.layer?.backgroundColor = terminalBackgroundColor.cgColor
        terminalContainer.layer?.borderWidth = 1
        terminalContainer.layer?.borderColor = NSColor.black.withAlphaComponent(0.6).cgColor
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalContainer)

        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.processDelegate = self
        terminal.caretColor = .systemGreen
        terminal.caretTextColor = .black
        terminal.nativeForegroundColor = .white
        terminal.nativeBackgroundColor = terminalBackgroundColor
        terminal.getTerminal().setCursorStyle(.steadyBlock)
        terminalContainer.addSubview(terminal)
        terminalView = terminal

        NSLayoutConstraint.activate([
            terminalContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            terminalContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            terminalContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            terminalContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),

            terminal.topAnchor.constraint(equalTo: terminalContainer.topAnchor, constant: 10),
            terminal.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor, constant: 10),
            terminal.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor, constant: -10),
            terminal.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor, constant: -10)
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
