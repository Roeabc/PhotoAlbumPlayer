import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var albumManager = AlbumManager()
    
    var body: some View {
        NavigationStack {
            Group {
                if albumManager.authorizationStatus == .authorized ||
                   albumManager.authorizationStatus == .limited {
                    albumListView
                } else {
                    requestAccessView
                }
            }
            .navigationTitle("相册")
        }
    }
    
    private var albumListView: some View {
        List(albumManager.albums) { album in
            NavigationLink(destination: AlbumDetailView(album: album, manager: albumManager)) {
                AlbumRow(album: album)
            }
        }
    }
    
    private var requestAccessView: some View {
        VStack(spacing: 16) {
            Text("需要相册访问权限")
                .font(.headline)
            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

struct AlbumRow: View {
    let album: AlbumInfo
    @State private var coverImage: UIImage? = nil
    
    var body: some View {
        HStack {
            if let coverImage = coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(6)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .cornerRadius(6)
            }
            VStack(alignment: .leading) {
                Text(album.title)
                    .font(.headline)
                Text("\(album.count) 张照片")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadCover()
        }
    }
    
    private func loadCover() {
        guard let asset = album.coverAsset else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false
        manager.requestImage(for: asset,
                             targetSize: CGSize(width: 120, height: 120),
                             contentMode: .aspectFill,
                             options: options) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.coverImage = image
                }
            }
        }
    }
}