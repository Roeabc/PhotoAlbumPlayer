import Foundation
import Photos

struct ImageScheme: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var imageIDs: [String]              // 选中的图片 ID
    var sourceAlbumIDs: [String]        // 来源相册的 localIdentifier 列表（合并时可能多个）
    var creationDate: Date = Date()
    
    // 获取该方案对应的 PHAsset 数组（保持顺序）
    func fetchAssets() -> [PHAsset] {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageIDs, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        var idToAsset: [String: PHAsset] = [:]
        for asset in assets {
            idToAsset[asset.localIdentifier] = asset
        }
        return imageIDs.compactMap { idToAsset[$0] }
    }
    
    // 获取来源相册的全部图片（合并去重，按加入顺序排列）
    func fetchAllAssetsFromSourceAlbums() -> [PHAsset] {
        var allAssets: [PHAsset] = []
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: sourceAlbumIDs, options: nil)
        collections.enumerateObjects { collection, _, _ in
            let fetched = PHAsset.fetchAssets(in: collection, options: nil)
            fetched.enumerateObjects { asset, _, _ in
                if !allAssets.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
                    allAssets.append(asset)
                }
            }
        }
        return allAssets
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
    
    func addScheme(name: String, imageIDs: [String], sourceAlbumIDs: [String]) {
        let scheme = ImageScheme(name: name, imageIDs: imageIDs, sourceAlbumIDs: sourceAlbumIDs)
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
        var allSourceIDs: [String] = []
        for scheme in selectedSchemes {
            allIDs.append(contentsOf: scheme.imageIDs)
            allSourceIDs.append(contentsOf: scheme.sourceAlbumIDs)
        }
        // 去重
        let uniqueIDs = Array(NSOrderedSet(array: allIDs)) as! [String]
        let uniqueSourceIDs = Array(NSOrderedSet(array: allSourceIDs)) as! [String]
        return ImageScheme(name: name, imageIDs: uniqueIDs, sourceAlbumIDs: uniqueSourceIDs)
    }
}