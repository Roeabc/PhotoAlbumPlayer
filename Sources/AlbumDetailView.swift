import SwiftUI
import Photos

// MARK: - 缩略图组件
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

// MARK: - 相册内页
struct AlbumDetailView: View {
    let album: AlbumInfo
    let manager: AlbumManager
    @State private var assets: [PHAsset] = []
    
    @State private var lastViewedID: String? = nil
    
    // 选择模式
    @State private var isSelecting = false
    @State private var selectedIndices: Set<Int> = []
    @State private var startIndex: Int? = nil
    
    @State private var showSelectedPlayback = false
    
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
    
    // MARK: - 选图工具栏
    private var selectionToolbar: some View {
        HStack {
            Text("已选 \(selectedIndices.count) 张")
            Spacer()
            Button("播放选中") {
                if !selectedIndices.isEmpty { showSelectedPlayback = true }
            }
            .disabled(selectedIndices.isEmpty)
            Button("取消选择") {
                clearSelection()
                isSelecting = false
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - 网格视图
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
        if let selected = selectedAssets() {
            NavigationLink(
                destination: PhotoDetailView(assets: selected, initialIndex: 0, lastViewedID: $lastViewedID),
                isActive: $showSelectedPlayback,
                label: { EmptyView() }
            )
            .hidden()
        }
    }
    
    // MARK: - 选图逻辑（核心修改）
    private func handleSelectionTap(index: Int) {
        guard let start = startIndex else {
            // 第一次点击：设置起点
            startIndex = index
            return
        }
        
        // 有起点，形成范围 [start, index]（可能单点）
        let range = min(start, index)...max(start, index)
        let indicesInRange = Set(range)
        
        if range.count == 1 {
            // 单张图片：直接反转这一张的状态
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
            } else {
                selectedIndices.insert(index)
            }
        } else {
            // 范围：对该范围内的所有索引统一反转
            // 即：已选 → 未选，未选 → 已选
            let currentlySelected = selectedIndices.intersection(indicesInRange)
            selectedIndices.subtract(currentlySelected)                // 取消已选的
            selectedIndices.formUnion(indicesInRange.subtracting(currentlySelected)) // 选中未选的
        }
        
        // 清除起点
        startIndex = nil
    }
    
    private func clearSelection() {
        selectedIndices = []
        startIndex = nil
    }
    
    private func selectedAssets() -> [PHAsset]? {
        guard !selectedIndices.isEmpty else { return nil }
        return selectedIndices.sorted().map { assets[$0] }
    }
}
