import Cocoa

class MainSplitViewController: NSSplitViewController {
    
    private var sidebarViewController: SidebarViewController!
    private var terminalTabViewController: TerminalTabViewController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 사이드바 (왼쪽) - 즐겨찾기 + 폴더 트리뷰
        sidebarViewController = SidebarViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 400
        
        // 콘텐츠 영역 (오른쪽) - 내장 터미널
        terminalTabViewController = TerminalTabViewController()
        let contentItem = NSSplitViewItem(viewController: terminalTabViewController)
        contentItem.minimumThickness = 400
        
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        
        // 사이드바에서 터미널 열기 요청 시
        sidebarViewController.onOpenTerminal = { [weak self] path in
            self?.terminalTabViewController.openTerminal(at: path)
        }

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        terminalTabViewController.openTerminal(at: homePath)
    }
}
