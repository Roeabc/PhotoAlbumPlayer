import SwiftUI
import Photos

// 缩略图组件
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
        .onAppear { loadThumbnail() }
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
                DispatchQueue.main.async { self.thumbnail = image }
            }
        }
    }
}

// 相册内页
struct AlbumDetailView: View {
    @EnvironmentObject var schemeStore: SchemeStore
    let album: AlbumInfo
    let manager: AlbumManager
    @State private var assets: [PHAsset] = []
    
    @State private var lastViewedID: String? = nil
    
    @State private var isSelecting = false
    @State private var selectedIndices: Set<Int> = []
    @State private var startIndex: Int? = nil
    
    @State private var showSelectedPlayback = false
    
    // 保存方案相关
    @State private var showSaveSchemeAlert = false
    @State private var newSchemeName = ""
    
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]
    
    var body: some View {
        VStack(spacing: 0) {
            if isSelecting { selectionToolbar }
            photoGrid
        }
        .navigationTitle(album.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isSelecting ? "完成" : "选择") {
                    isSelecting.toggle()
                    if !isSelecting { clearSelection() }
                }
            }
        }
        .onAppear {
            assets = manager.fetchAssets(for: album)
        }
    }
    
    private var selectionToolbar: some View {
        HStack {
            Text("已选 \(selectedIndices.count) 张")
            Spacer()
            Button("播放选中") {
                if !selectedIndices.isEmpty { showSelectedPlayback = true }
            }
            .disabled(selectedIndices.isEmpty)
            Button("保存方案") {
                showSaveSchemeAlert = true
            }
            .disabled(selectedIndices.isEmpty)
            Button("取消选择") {
                clearSelection()
                isSelecting = false
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .alert("保存方案", isPresented: $showSaveSchemeAlert) {
            TextField("方案名称", text: $newSchemeName)
            Button("保存") {
                saveCurrentSelection()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("为当前选中的 \(selectedIndices.count) 张图片命名")
        }
    }
    
    private var photoGrid: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                        gridCell(index: index, asset: asset)
                            .id(asset.localIdentifier)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: lastViewedID) { newID in
                if let id = newID {
                    withAnimation { scrollProxy.scrollTo(id, anchor: .center) }
                    lastViewedID = nil
                }
            }
        }
        .overlay(selectedPlaybackLink)
    }
    
    @ViewBuilder
    private func gridCell(index: Int, asset: PHAsset) -> some View {
        ZStack {
            if isSelecting {
                PhotoCell(asset: asset)
                    .overlay(selectionOverlay(index: index))
                    .onTapGesture { handleSelectionTap(index: index) }
            } else {
                NavigationLink(destination: PhotoDetailView(
                    assets: assets,
                    initialIndex: index,
                    lastViewedID: $lastViewedID
                )) {
                    PhotoCell(asset: asset)
                }
            }
        }
    }
    
    @ViewBuilder
    private func selectionOverlay(index: Int) -> some View {
        if selectedIndices.contains(index) {
            Rectangle()
                .stroke(Color.blue, lineWidth: 3)
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .padding(4)
                }
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private var selectedPlaybackLink: some View {
        if !selectedIndices.isEmpty {
            let selectedAssets = selectedIndices.sorted().map { assets[$0] }
            NavigationLink(
                destination: PhotoDetailView(assets: selectedAssets, initialIndex: 0, lastViewedID: $lastViewedID),
                isActive: $showSelectedPlayback,
                label: { EmptyView() }
            )
            .hidden()
        }
    }
    
    private func handleSelectionTap(index: Int) {
        guard let start = startIndex else {
            startIndex = index
            return
        }
        let range = min(start, index)...max(start, index)
        let indicesInRange = Set(range)
        if range.count == 1 {
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
            } else {
                selectedIndices.insert(index)
            }
        } else {
            let currentlySelected = selectedIndices.intersection(indicesInRange)
            selectedIndices.subtract(currentlySelected)
            selectedIndices.formUnion(indicesInRange.subtracting(currentlySelected))
        }
        startIndex = nil
    }
    
    private func clearSelection() {
        selectedIndices = []
        startIndex = nil
    }
    
    private func saveCurrentSelection() {
        let name = newSchemeName.isEmpty ? "方案 \(schemeStore.schemes.count + 1)" : newSchemeName
        let ids = selectedIndices.sorted().map { assets[$0].localIdentifier }
        // 记录来源相册ID（当前相册）
        schemeStore.addScheme(name: name, imageIDs: ids, sourceAlbumIDs: [album.id])
        newSchemeName = ""
    }