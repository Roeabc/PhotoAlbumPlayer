import SwiftUI
import Photos

struct AlbumDetailView: View {
    let album: AlbumInfo
    let manager: AlbumManager
    @State private var assets: [PHAsset] = []
    
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    NavigationLink(destination: PhotoDetailView(assets: assets, initialIndex: index)) {
                        PhotoCell(asset: asset)
                    }
                }
            }
        }
        .navigationTitle(album.title)
        .onAppear {
            assets = manager.fetchAssets(for: album)
        }
    }
}

struct PhotoCell: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.1)
            }
        }
        .frame(width: (UIScreen.main.bounds.width - 6) / 3,
               height: (UIScreen.main.bounds.width - 6) / 3)
        .clipped()
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        let size = CGSize(width: 200, height: 200)
        manager.requestImage(for: asset,
                             targetSize: size,
                             contentMode: .aspectFill,
                             options: options) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.thumbnail = image
                }
            }
        }
    }
}