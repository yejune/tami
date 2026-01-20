import Foundation

struct Favorite: Codable {
    var name: String
    let path: String
    let dateAdded: Date
    
    init(url: URL) {
        self.name = url.lastPathComponent
        self.path = url.path
        self.dateAdded = Date()
    }
}

class FavoritesManager {
    static let shared = FavoritesManager()
    
    private(set) var favorites: [Favorite] = []
    
    private var savePath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Tami")
        
        // 폴더가 없으면 생성
        if !FileManager.default.fileExists(atPath: appFolder.path) {
            try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }
        
        return appFolder.appendingPathComponent("favorites.json")
    }
    
    private init() {
        load()
    }
    
    func addFavorite(_ url: URL) {
        // 중복 체크
        guard !favorites.contains(where: { $0.path == url.path }) else {
            return
        }
        
        let favorite = Favorite(url: url)
        favorites.append(favorite)
        save()
    }
    
    func removeFavorite(at index: Int) {
        guard index >= 0 && index < favorites.count else { return }
        favorites.remove(at: index)
        save()
    }

    func renameFavorite(at index: Int, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard index >= 0 && index < favorites.count,
              !trimmedName.isEmpty else { return }
        favorites[index].name = trimmedName
        save()
    }

    func moveFavorites(from indexes: IndexSet, to destination: Int) {
        guard !indexes.isEmpty else { return }
        var updated = favorites
        let moving = indexes.map { updated[$0] }
        for index in indexes.sorted(by: >) {
            updated.remove(at: index)
        }
        let adjustedDestination = max(0, min(destination - indexes.filter { $0 < destination }.count, updated.count))
        for (offset, item) in moving.enumerated() {
            updated.insert(item, at: adjustedDestination + offset)
        }
        favorites = updated
        save()
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(favorites)
            try data.write(to: savePath)
        } catch {
            print("Failed to save favorites: \(error)")
        }
    }
    
    private func load() {
        do {
            let data = try Data(contentsOf: savePath)
            favorites = try JSONDecoder().decode([Favorite].self, from: data)
        } catch {
            // 파일이 없거나 읽기 실패 시 빈 배열로 시작
            favorites = []
        }
    }
}
