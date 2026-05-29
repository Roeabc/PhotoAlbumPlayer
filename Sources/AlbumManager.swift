import Photos
import SwiftUI

class AlbumManager: ObservableObject {
    @Published var albums: [AlbumInfo] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    init() {
        checkAuthorization()
    }
    
    func checkAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorizationStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
                DispatchQueue.main.async {
                    self?.authorizationStatus = status
                    if status == .authorized || status == .limited {
                        self?.fetchAlbums()
                    }
                }
            }
        } else if authorizationStatus == .authorized || authorizationStatus == .limited {
            fetchAlbums()
        }
    }
    
    func fetchAlbums() {
        var resultAlbums: [AlbumInfo] = []
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbums.enumerateObjects { collection, _, _ in
            self.addCollection(collection, to: &resultAlbums)
        }
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            self.addCollection(collection, to: &resultAlbums)
        }
        albums = resultAlbums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    private func addCollection(_ collection: PHAssetCollection, to albums: inout [AlbumInfo]) {
        let assets = PHAsset.fetchAssets(in: collection, options: nil)
        if assets.count > 0 {
            let coverAsset = assets.firstObject
            albums.append(AlbumInfo(id: collection.localIdentifier,
                                    title: collection.localizedTitle ?? "未命名",
                                    count: assets.count,
                                    coverAsset: coverAsset))
        }
    }
    
    func fetchAssets(for album: AlbumInfo) -> [PHAsset] {
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil).firstObject else { return [] }
        let fetchResult = PHAsset.fetchAssets(in: collection, options: nil)
        var assets = [PHAsset]()
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
}

struct AlbumInfo: Identifiable {
    let id: String
    let title: String
    let count: Int
    let coverAsset: PHAsset?
}