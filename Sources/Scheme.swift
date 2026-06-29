import Foundation
import Photos

struct ImageScheme: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var imageIDs: [String]  // PHAsset.localIdentifier 列表
    var creationDate: Date = Date()
    
    // 获取该方案对应的 PHAsset 数组（需在获取权限后调用）
    func fetchAssets() -> [PHAsset] {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageIDs, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        // 按照 imageIDs 的顺序排序（fetchAssets 不保证顺序）
        var idToAsset: [String: PHAsset] = [:]
        for asset in assets {
            idToAsset[asset.localIdentifier] = asset
        }
        return imageIDs.compactMap { idToAsset[$0] }
    }
}

class SchemeStore: ObservableObject {
    @Published var schemes: [ImageScheme] = []
    
    private let key = "saved_schemes"
    
    init() {
        load()
    }
    
    func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            schemes = try JSONDecoder().decode([ImageScheme].self, from: data)
        } catch {
            print("加载方案失败: \(error)")
        }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(schemes)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("保存方案失败: \(error)")
        }
    }
    
    func addScheme(name: String, imageIDs: [String]) {
        let scheme = ImageScheme(name: name, imageIDs: imageIDs)
        schemes.append(scheme)
        save()
    }
    
    func updateScheme(_ scheme: ImageScheme) {
        if let index = schemes.firstIndex(where: { $0.id == scheme.id }) {
            schemes[index] = scheme
            save()
        }
    }
    
    func deleteScheme(_ scheme: ImageScheme) {
        schemes.removeAll { $0.id == scheme.id }
        save()
    }
    
    func mergeSchemes(_ selectedSchemes: [ImageScheme], name: String) -> ImageScheme {
        var allIDs: [String] = []
        for scheme in selectedSchemes {
            allIDs.append(contentsOf: scheme.imageIDs)
        }
        // 去重并保持顺序（这里简单去重，不保证原始顺序）
        let uniqueIDs = Array(NSOrderedSet(array: allIDs)) as! [String]
        return ImageScheme(name: name, imageIDs: uniqueIDs)
    }
}