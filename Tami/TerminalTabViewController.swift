import Cocoa

final class TerminalTabViewController: NSTabViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .unspecified
        tabView.tabViewType = .topTabsBezelBorder
        tabView.drawsBackground = true
        tabView.wantsLayer = true
        tabView.layer?.backgroundColor = NSColor.systemOrange.cgColor
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let containerInset: CGFloat = 10
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: containerInset),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -containerInset),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -containerInset)
        ])

        tabView.removeFromSuperview()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: container.topAnchor),
            tabView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleTabRightClick(_:)))
        rightClick.buttonMask = 0x2
        tabView.addGestureRecognizer(rightClick)
    }
    
    func openTerminal(at path: String) {
        if let existingIndex = tabViewItems.firstIndex(where: { item in
            guard let terminalVC = item.viewController as? TerminalViewController else { return false }
            return terminalVC.currentPath == path
        }) {
            selectedTabViewItemIndex = existingIndex
            (tabViewItems[existingIndex].viewController as? TerminalViewController)?.focusTerminal()
            return
        }
        
        let terminalVC = TerminalViewController()
        terminalVC.loadViewIfNeeded()
        
        let tabItem = NSTabViewItem(viewController: terminalVC)
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        tabItem.label = folderName.isEmpty ? path : folderName
        
        addTabViewItem(tabItem)
        selectedTabViewItemIndex = tabViewItems.count - 1
        terminalVC.openTerminal(at: path)
    }

    @objc private func handleTabRightClick(_ sender: NSClickGestureRecognizer) {
        let point = sender.location(in: tabView)
        guard let tabViewItem = tabView.tabViewItem(at: point) else { return }

        let menu = NSMenu()
        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(closeTabFromMenu(_:)), keyEquivalent: "")
        closeItem.target = self
        closeItem.representedObject = tabViewItem
        menu.addItem(closeItem)

        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: tabView)
    }

    @objc private func closeTabFromMenu(_ sender: NSMenuItem) {
        guard let tabViewItem = sender.representedObject as? NSTabViewItem else { return }
        removeTabViewItem(tabViewItem)
    }
}
