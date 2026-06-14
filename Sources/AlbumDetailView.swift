import SwiftUI
import Photos

// 相册网格中的缩略图单元格
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

// 相册内页：网格 + 选择 + 播放
struct AlbumDetailView: View {
    let album: AlbumInfo
    let manager: AlbumManager
    @State private var assets: [PHAsset] = []
    
    // 返回定位
    @State private var lastViewedID: String? = nil
    
    // 选图模式
    @State private var isSelecting = false
    @State private var selectedIndices: Set<Int> = []
    @State private var startIndex: Int? = nil
    
    // 播放选中图片的导航
    @State private var showSelectedPlayback = false
    
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]
    
    var body: some View {
        VStack(spacing: 0) {
            if isSelecting {
                selectionToolbar
            }
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
    
    // 选图模式底部工具栏
    private var selectionToolbar: some View {
        HStack {
            Text("已选 \(selectedIndices.count) 张")
            Spacer()
            Button("播放选中") {
                if !selectedIndices.isEmpty {
                    showSelectedPlayback = true
                }
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
    
    // 图片网格 + 滚动定位
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
    
    // 每个网格项
    @ViewBuilder
    private func gridCell(index: Int, asset: PHAsset) -> some View {
        ZStack {
            if isSelecting {
                // 选图模式：点击处理选择，不可直接跳转
                PhotoCell(asset: asset)
                    .overlay(selectionOverlay(index: index))
                    .onTapGesture { handleSelectionTap(index: index) }
            } else {
                // 正常浏览：点击进入大图
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
    
    // 选中图片的覆盖层（蓝色边框 + 勾）
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
    
    // 隐藏的导航：用于播放选中的图片
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
    
    // MARK: - 选图逻辑
    private func handleSelectionTap(index: Int) {
        guard let start = startIndex else {
            startIndex = index
            return
        }
        
        let range = min(start, index)...max(start, index)
        let indices = Set(range)
        let startSelected = selectedIndices.contains(start)
        let endSelected = selectedIndices.contains(index)
        
        if startSelected && endSelected {
            selectedIndices.subtract(indices)
        } else if !startSelected && !endSelected {
            selectedIndices.formUnion(indices)
        } else {
            let intersection = selectedIndices.intersection(indices)
            selectedIndices.subtract(intersection)
            selectedIndices.formUnion(indices.subtracting(intersection))
        }
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
