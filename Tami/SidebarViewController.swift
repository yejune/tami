import Cocoa

// 폴더 노드 모델
class FolderNode {
    let url: URL
    let name: String
    var children: [FolderNode]?
    var isExpanded: Bool = false
    let isDirectory: Bool
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
    
    func loadChildren() {
        guard children == nil, isDirectory else { return }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            children = contents
                .sorted { lhs, rhs in
                    let lhsIsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let rhsIsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if lhsIsDir != rhsIsDir {
                        return lhsIsDir && !rhsIsDir
                    }
                    return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
                }
                .map { FolderNode(url: $0) }
        } catch {
            children = []
        }
    }
}

class SidebarViewController: NSViewController {
    
    private var containerView: NSView!

    // 즐겨찾기 테이블뷰
    private var favoritesTableView: NSTableView!
    private var favoritesScrollView: NSScrollView!
    private var favoritesContainerView: NSView!
    private var favoritesHeader: NSTextField!
    private var emptyFavoritesLabel: NSTextField!
    private var favoritesHeightConstraint: NSLayoutConstraint!
    private var dividerView: ResizeDividerView!
    private var folderHeader: NSTextField!
    private var isFavoritesHeightUserAdjusted = false
    private var dragStartFavoritesHeight: CGFloat = 0
    
    // 폴더 트리뷰
    private var outlineView: ToggleOutlineView!
    private var folderScrollView: NSScrollView!
    
    private var rootNode: FolderNode!

    private let containerInset: CGFloat = 10
    private let headerTopPadding: CGFloat = 10
    private let headerHorizontalPadding: CGFloat = 10
    private let listHorizontalPadding: CGFloat = 0
    private let headerToListSpacing: CGFloat = 2
    private let sectionSpacing: CGFloat = 6
    private let dividerHeight: CGFloat = 8
    private let rowHeight: CGFloat = 24
    private let minFolderHeight: CGFloat = 120
    
    // 터미널 열기 콜백
    var onOpenTerminal: ((String) -> Void)?
    var onOpenFile: ((URL) -> Void)?
    
    override func loadView() {
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 250, height: 500))
        effectView.material = .sidebar
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        view = effectView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadHomeDirectory()
        updateFavoritesHeight()
        updateSidebarColors()
    }

    deinit {
    }
    
    private func setupUI() {
        let containerEffectView = NSVisualEffectView()
        containerEffectView.material = .sidebar
        containerEffectView.state = .active
        containerEffectView.blendingMode = .withinWindow
        containerEffectView.wantsLayer = true
        containerEffectView.layer?.cornerRadius = 10
        containerEffectView.layer?.masksToBounds = true
        containerView = containerEffectView
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // ===== 즐겨찾기 섹션 =====
        favoritesHeader = NSTextField(labelWithString: "Favorites")
        favoritesHeader.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        favoritesHeader.textColor = NSColor.secondaryLabelColor
        favoritesHeader.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(favoritesHeader)

        favoritesContainerView = NSView()
        favoritesContainerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(favoritesContainerView)

        favoritesScrollView = NSScrollView()
        favoritesScrollView.translatesAutoresizingMaskIntoConstraints = false
        favoritesScrollView.hasVerticalScroller = true
        favoritesScrollView.autohidesScrollers = true
        favoritesScrollView.borderType = .noBorder
        favoritesScrollView.drawsBackground = false
        favoritesScrollView.automaticallyAdjustsContentInsets = false
        favoritesScrollView.contentInsets = NSEdgeInsetsZero
        favoritesScrollView.contentView.contentInsets = NSEdgeInsetsZero
        
        favoritesTableView = NSTableView()
        favoritesTableView.rowHeight = rowHeight
        favoritesTableView.headerView = nil
        favoritesTableView.style = .plain
        favoritesTableView.backgroundColor = .clear
        favoritesTableView.intercellSpacing = NSSize(width: 0, height: 0)
        favoritesTableView.registerForDraggedTypes([.tamiFavoriteIndex, .fileURL])
        favoritesTableView.setDraggingSourceOperationMask(.move, forLocal: true)
        
        let favColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FavColumn"))
        favColumn.width = 200
        favColumn.isEditable = true
        favoritesTableView.addTableColumn(favColumn)
        
        favoritesTableView.dataSource = self
        favoritesTableView.delegate = self
        favoritesTableView.target = self
        favoritesTableView.doubleAction = #selector(favoriteDoubleClicked(_:))
        
        // 즐겨찾기 우클릭 메뉴
        let favMenu = NSMenu()
        favMenu.addItem(NSMenuItem(title: "Open in Terminal", action: #selector(openFavoriteInTerminal(_:)), keyEquivalent: ""))
        favMenu.addItem(NSMenuItem(title: "Rename", action: #selector(renameFavorite(_:)), keyEquivalent: ""))
        favMenu.addItem(NSMenuItem(title: "Remove from Favorites", action: #selector(removeFromFavorites(_:)), keyEquivalent: ""))
        favoritesTableView.menu = favMenu
        
        favoritesScrollView.documentView = favoritesTableView
        favoritesContainerView.addSubview(favoritesScrollView)

        emptyFavoritesLabel = NSTextField(labelWithString: "No Favorites")
        emptyFavoritesLabel.font = NSFont.systemFont(ofSize: 12)
        emptyFavoritesLabel.textColor = NSColor.tertiaryLabelColor
        emptyFavoritesLabel.alignment = .center
        emptyFavoritesLabel.translatesAutoresizingMaskIntoConstraints = false
        favoritesContainerView.addSubview(emptyFavoritesLabel)
        
        // ===== 구분선 =====
        dividerView = ResizeDividerView()
        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(dividerView)

        let dividerLine = NSView()
        dividerLine.translatesAutoresizingMaskIntoConstraints = false
        dividerLine.wantsLayer = true
        dividerLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        dividerView.addSubview(dividerLine)

        let dividerPan = NSPanGestureRecognizer(target: self, action: #selector(handleDividerPan(_:)))
        dividerView.addGestureRecognizer(dividerPan)

        // ===== 폴더 트리 섹션 =====
        folderHeader = NSTextField(labelWithString: "Home")
        folderHeader.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        folderHeader.textColor = NSColor.secondaryLabelColor
        folderHeader.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(folderHeader)
        
        folderScrollView = NSScrollView()
        folderScrollView.translatesAutoresizingMaskIntoConstraints = false
        folderScrollView.hasVerticalScroller = true
        folderScrollView.autohidesScrollers = true
        folderScrollView.borderType = .noBorder
        folderScrollView.drawsBackground = false
        folderScrollView.automaticallyAdjustsContentInsets = false
        folderScrollView.contentInsets = NSEdgeInsetsZero
        folderScrollView.contentView.contentInsets = NSEdgeInsetsZero
        
        outlineView = ToggleOutlineView()
        outlineView.headerView = nil
        outlineView.rowHeight = rowHeight
        outlineView.style = .plain
        outlineView.indentationPerLevel = 16
        outlineView.autoresizesOutlineColumn = true
        outlineView.backgroundColor = .clear
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.onToggleItem = { [weak self] item in
            guard let self,
                  let node = item as? FolderNode,
                  node.isDirectory else { return }

            if self.outlineView.isItemExpanded(node) {
                self.outlineView.collapseItem(node)
            } else {
                self.outlineView.expandItem(node)
            }
        }
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FolderColumn"))
        column.title = "Folders"
        column.width = 200
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView.onDoubleClickItem = { [weak self] item in
            guard let self, let node = item as? FolderNode else { return }
            if node.isDirectory {
                self.onOpenTerminal?(node.url.path)
            } else {
                self.onOpenFile?(node.url)
            }
        }
        
        // 폴더 우클릭 메뉴
        let folderMenu = NSMenu()
        folderMenu.addItem(NSMenuItem(title: "Add to Favorites", action: #selector(addToFavorites(_:)), keyEquivalent: ""))
        folderMenu.addItem(NSMenuItem(title: "Open in Terminal", action: #selector(openFolderInTerminal(_:)), keyEquivalent: ""))
        outlineView.menu = folderMenu
        
        folderScrollView.documentView = outlineView
        containerView.addSubview(folderScrollView)
        
        // ===== 레이아웃 =====
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor, constant: containerInset),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: containerInset),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -containerInset),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -containerInset),

            // 즐겨찾기 헤더
            favoritesHeader.topAnchor.constraint(equalTo: containerView.topAnchor, constant: headerTopPadding),
            favoritesHeader.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: headerHorizontalPadding),
            favoritesHeader.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -headerHorizontalPadding),
            
            // 즐겨찾기 컨테이너
            favoritesContainerView.topAnchor.constraint(equalTo: favoritesHeader.bottomAnchor, constant: headerToListSpacing),
            favoritesContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: listHorizontalPadding),
            favoritesContainerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -listHorizontalPadding),
            
            dividerView.topAnchor.constraint(equalTo: favoritesContainerView.bottomAnchor, constant: sectionSpacing),
            dividerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            dividerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            dividerView.heightAnchor.constraint(equalToConstant: dividerHeight),

            // 폴더 헤더
            folderHeader.topAnchor.constraint(equalTo: dividerView.bottomAnchor, constant: sectionSpacing),
            folderHeader.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: headerHorizontalPadding),
            folderHeader.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -headerHorizontalPadding),
            
            // 폴더 트리 (나머지 공간)
            folderScrollView.topAnchor.constraint(equalTo: folderHeader.bottomAnchor, constant: headerToListSpacing),
            folderScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            folderScrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            folderScrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        favoritesHeightConstraint = favoritesContainerView.heightAnchor.constraint(equalToConstant: 0)
        favoritesHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            favoritesScrollView.topAnchor.constraint(equalTo: favoritesContainerView.topAnchor),
            favoritesScrollView.leadingAnchor.constraint(equalTo: favoritesContainerView.leadingAnchor),
            favoritesScrollView.trailingAnchor.constraint(equalTo: favoritesContainerView.trailingAnchor),
            favoritesScrollView.bottomAnchor.constraint(equalTo: favoritesContainerView.bottomAnchor),

            emptyFavoritesLabel.centerXAnchor.constraint(equalTo: favoritesContainerView.centerXAnchor),
            emptyFavoritesLabel.centerYAnchor.constraint(equalTo: favoritesContainerView.centerYAnchor),
            emptyFavoritesLabel.leadingAnchor.constraint(equalTo: favoritesContainerView.leadingAnchor),
            emptyFavoritesLabel.trailingAnchor.constraint(equalTo: favoritesContainerView.trailingAnchor)
        ])

        if let dividerLine = dividerView.subviews.first {
            NSLayoutConstraint.activate([
                dividerLine.centerYAnchor.constraint(equalTo: dividerView.centerYAnchor),
                dividerLine.leadingAnchor.constraint(equalTo: dividerView.leadingAnchor),
                dividerLine.trailingAnchor.constraint(equalTo: dividerView.trailingAnchor),
                dividerLine.heightAnchor.constraint(equalToConstant: 1)
            ])
        }
    }

    private func updateSidebarColors() {
        containerView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    private func loadHomeDirectory() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        rootNode = FolderNode(url: homeURL)
        rootNode.loadChildren()
        outlineView.reloadData()
    }
    
    func reloadFavorites() {
        favoritesTableView.reloadData()
        updateFavoritesHeight()
    }

    private func updateFavoritesHeight() {
        if isFavoritesHeightUserAdjusted {
            return
        }
        let rows = FavoritesManager.shared.favorites.count
        let contentHeight = CGFloat(rows) * favoritesTableView.rowHeight
        let maxHeight: CGFloat = 200
        if rows == 0 {
            favoritesHeightConstraint.constant = favoritesTableView.rowHeight
            favoritesScrollView.isHidden = true
            emptyFavoritesLabel.isHidden = false
        } else {
            favoritesHeightConstraint.constant = min(contentHeight, maxHeight)
            favoritesScrollView.isHidden = false
            emptyFavoritesLabel.isHidden = true
        }
        containerView?.layoutSubtreeIfNeeded()
        favoritesHeightConstraint.constant = clampFavoritesHeight(favoritesHeightConstraint.constant)
    }

    private func clampFavoritesHeight(_ height: CGFloat) -> CGFloat {
        guard let containerView else { return height }
        containerView.layoutSubtreeIfNeeded()
        let favoritesHeaderHeight = favoritesHeader.intrinsicContentSize.height
        let folderHeaderHeight = folderHeader.intrinsicContentSize.height
        let fixed = headerTopPadding
            + favoritesHeaderHeight
            + headerToListSpacing
            + sectionSpacing
            + dividerHeight
            + sectionSpacing
            + folderHeaderHeight
            + headerToListSpacing
        let maxHeight = max(0, containerView.bounds.height - fixed - minFolderHeight)
        let minHeight: CGFloat = 0
        return min(max(height, minHeight), maxHeight)
    }

    @objc private func handleDividerPan(_ recognizer: NSPanGestureRecognizer) {
        guard let containerView else { return }
        let translation = recognizer.translation(in: containerView)
        switch recognizer.state {
        case .began:
            isFavoritesHeightUserAdjusted = true
            dragStartFavoritesHeight = favoritesHeightConstraint.constant
        case .changed:
            let newHeight = dragStartFavoritesHeight - translation.y
            favoritesHeightConstraint.constant = clampFavoritesHeight(newHeight)
        case .ended, .cancelled:
            favoritesHeightConstraint.constant = clampFavoritesHeight(favoritesHeightConstraint.constant)
        default:
            break
        }
    }
    
    // MARK: - Actions
    
    @objc private func favoriteDoubleClicked(_ sender: Any) {
        let row = favoritesTableView.clickedRow
        guard row >= 0 else { return }
        let favorite = FavoritesManager.shared.favorites[row]
        openFavoritePath(favorite.path)
    }
    
    @objc private func openFavoriteInTerminal(_ sender: Any) {
        let row = favoritesTableView.clickedRow
        guard row >= 0 else { return }
        let favorite = FavoritesManager.shared.favorites[row]
        onOpenTerminal?(favorite.path)
    }
    
    @objc private func removeFromFavorites(_ sender: Any) {
        let row = favoritesTableView.clickedRow
        guard row >= 0 else { return }
        FavoritesManager.shared.removeFavorite(at: row)
        reloadFavorites()
    }

    @objc private func renameFavorite(_ sender: Any) {
        let row = favoritesTableView.clickedRow
        guard row >= 0 else { return }
        let columnIndex = favoritesTableView.column(withIdentifier: NSUserInterfaceItemIdentifier("FavColumn"))
        guard columnIndex >= 0 else { return }
        favoritesTableView.editColumn(columnIndex, row: row, with: nil, select: true)
    }
    
    @objc private func addToFavorites(_ sender: Any) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let item = outlineView.item(atRow: clickedRow) as? FolderNode else {
            return
        }
        
        FavoritesManager.shared.addFavorite(item.url)
        reloadFavorites()
    }
    
    @objc private func openFolderInTerminal(_ sender: Any) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let item = outlineView.item(atRow: clickedRow) as? FolderNode else {
            return
        }
        onOpenTerminal?(item.url.path)
    }


    private func removeFavorites(at indexes: IndexSet) {
        guard !indexes.isEmpty else { return }
        for index in indexes.sorted(by: >) {
            FavoritesManager.shared.removeFavorite(at: index)
        }
        reloadFavorites()
    }

    private func openFavoritePath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            onOpenTerminal?(url.path)
        } else {
            onOpenFile?(url)
        }
    }
}

final class ResizeDividerView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}

// MARK: - NSOutlineViewDataSource
extension SidebarViewController: NSOutlineViewDataSource {
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootNode?.children?.count ?? 0
        }
        
        if let node = item as? FolderNode {
            node.loadChildren()
            return node.children?.count ?? 0
        }
        
        return 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return rootNode.children![index]
        }
        
        if let node = item as? FolderNode {
            return node.children![index]
        }
        
        fatalError("Unexpected item")
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? FolderNode {
            // Defer loading child directories to avoid triggering privacy prompts on launch.
            return node.isDirectory
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? FolderNode else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(node.url.absoluteString, forType: .fileURL)
        return pasteboardItem
    }
}

// MARK: - NSOutlineViewDelegate
extension SidebarViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FolderNode else { return nil }
        
        let identifier = NSUserInterfaceItemIdentifier("FolderCell")
        var cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        
        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = identifier
            
            let spacerView = NSView()
            spacerView.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(spacerView)

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(imageView)
            cellView?.imageView = imageView
            
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cellView?.addSubview(textField)
            cellView?.textField = textField
            
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
            ])
        }
        
        cellView?.textField?.stringValue = node.name
        cellView?.imageView?.image = NSWorkspace.shared.icon(forFile: node.url.path)
        
        return cellView
    }

}

final class ToggleOutlineView: NSOutlineView {
    var onToggleItem: ((Any) -> Void)?
    var onDoubleClickItem: ((Any) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let row = row(at: clickPoint)

        if event.clickCount == 2, row >= 0, let item = item(atRow: row) {
            super.mouseDown(with: event)
            onDoubleClickItem?(item)
            return
        }

        if row >= 0 {
            let outlineCellRect = frameOfOutlineCell(atRow: row)
            if !outlineCellRect.contains(clickPoint), let item = item(atRow: row) {
                onToggleItem?(item)
            }
        }

        super.mouseDown(with: event)
    }
}

// MARK: - NSTableViewDataSource & Delegate (Favorites)
extension SidebarViewController: NSTableViewDataSource, NSTableViewDelegate {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return FavoritesManager.shared.favorites.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let favorite = FavoritesManager.shared.favorites[row]
        let identifier = NSUserInterfaceItemIdentifier("FavCell")
        
        var cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        
        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = identifier
            
            let spacerView = NSView()
            spacerView.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(spacerView)

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(imageView)
            cellView?.imageView = imageView
            
            let textField = NSTextField()
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.font = NSFont.systemFont(ofSize: 12)
            textField.isBordered = false
            textField.drawsBackground = false
            textField.isEditable = true
            textField.isSelectable = true
            cellView?.addSubview(textField)
            cellView?.textField = textField
            
            NSLayoutConstraint.activate([
                spacerView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 2),
                spacerView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                spacerView.widthAnchor.constraint(equalToConstant: 16),
                spacerView.heightAnchor.constraint(equalToConstant: 1),

                imageView.leadingAnchor.constraint(equalTo: spacerView.trailingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
            ])
        }
        
        cellView?.textField?.stringValue = favorite.name
        cellView?.imageView?.image = NSWorkspace.shared.icon(forFile: favorite.path)
        
        return cellView
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return tableColumn?.identifier == NSUserInterfaceItemIdentifier("FavColumn")
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard tableColumn?.identifier == NSUserInterfaceItemIdentifier("FavColumn") else { return }
        if let name = object as? String {
            FavoritesManager.shared.renameFavorite(at: row, to: name)
            reloadFavorites()
        }
    }

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: rowIndexes, requiringSecureCoding: false)
        pboard.declareTypes([.tamiFavoriteIndex], owner: self)
        if let data {
            pboard.setData(data, forType: .tamiFavoriteIndex)
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        if pasteboard.data(forType: .tamiFavoriteIndex) != nil {
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }
        if pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) != nil {
            tableView.setDropRow(row, dropOperation: .above)
            return .copy
        }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let pasteboard = info.draggingPasteboard
        if let data = pasteboard.data(forType: .tamiFavoriteIndex),
           let indexSet = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSIndexSet.self], from: data) as? IndexSet {
            let destination = min(max(row, 0), FavoritesManager.shared.favorites.count)
            FavoritesManager.shared.moveFavorites(from: indexSet, to: destination)
            reloadFavorites()
            return true
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                FavoritesManager.shared.addFavorite(url)
            }
            reloadFavorites()
            return true
        }

        return false
    }
}

extension NSPasteboard.PasteboardType {
    static let tamiFavoriteIndex = NSPasteboard.PasteboardType("com.tami.favorite-index")
}
