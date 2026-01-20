import Cocoa

final class TerminalTabViewController: NSTabViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .segmentedControlOnTop
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
}
