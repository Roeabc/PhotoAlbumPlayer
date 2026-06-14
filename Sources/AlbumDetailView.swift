import SwiftUI
import Photos

struct AlbumDetailView: View {
    let album: AlbumInfo
    let manager: AlbumManager
    @State private var assets: [PHAsset] = []
    
    // 返回位置记录
    @State private var lastViewedID: String? = nil
    
    // 选图模式
    @State private var isSelecting = false
    @State private var selectedIndices: Set<Int> = []      // 当前选中的索引
    @State private var startIndex: Int? = nil               // 范围起点
    
    // 播放选图的导航触发
    @State private var showSelectedPlayback = false
    
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]
    
    var body: some View {
        VStack(spacing: 0) {
            // 选图模式工具栏
            if isSelecting {
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
            
            // 网格
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                            ZStack {
                                // 正常浏览的导航链接（选图模式下禁用）
                                NavigationLink(
                                    destination: PhotoDetailView(
                                        assets: assets,
                                        initialIndex: index,
                                        lastViewedID: $lastViewedID
                                    )
                                ) {
                                    PhotoCell(asset: asset)
                                }
                                .disabled(isSelecting)
                                
                                // 选图模式下的点击操作
                                if isSelecting {
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            handleSelectionTap(index: index)
                                        }
                                    
                                    // 选中高亮
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
                            }
                            .id(asset.localIdentifier)   // 用于滚动定位
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: lastViewedID) { newID in
                    if let id = newID {
                        withAnimation {
                            scrollProxy.scrollTo(id, anchor: .center)
                        }
                        lastViewedID = nil
                    }
                }
            }
            
            // 隐藏的导航链接：播放选中图片
            NavigationLink(
                destination: selectedAssets().map {
                    PhotoDetailView(assets: $0, initialIndex: 0, lastViewedID: $lastViewedID)
                },
                isActive: $showSelectedPlayback
            ) { EmptyView() }
            .hidden()
        }
        .navigationTitle(album.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isSelecting ? "完成" : "选择") {
                    isSelecting.toggle()
                    if !isSelecting {
                        clearSelection()
                    }
                }
            }
        }
        .onAppear {
            assets = manager.fetchAssets(for: album)
        }
    }
    
    // MARK: - 选图逻辑
    private func handleSelectionTap(index: Int) {
        guard let start = startIndex else {
            // 没有起点，设置起点
            startIndex = index
            return
        }
        
        // 已有起点，完成范围选择
        let range = min(start, index)...max(start, index)
        let indicesInRange = Set(range)
        let startSelected = selectedIndices.contains(start)
        let endSelected = selectedIndices.contains(index)
        
        if startSelected && endSelected {
            // 都选中 → 取消区间内所有选中的图
            selectedIndices.subtract(indicesInRange)
        } else if !startSelected && !endSelected {
            // 都未选中 → 选中区间内所有图
            selectedIndices.formUnion(indicesInRange)
        } else {
            // 一选一未选 → 互补转换
            let intersection = selectedIndices.intersection(indicesInRange)
            selectedIndices.subtract(intersection)
            selectedIndices.formUnion(indicesInRange.subtracting(intersection))
        }
        
        // 清除起点
        startIndex = nil
    }
    
    private func clearSelection() {
        selectedIndices = []
        startIndex = nil
    }
    
    // 获取选中的资产（按原顺序）
    private func selectedAssets() -> [PHAsset]? {
        guard !selectedIndices.isEmpty else { return nil }
        let sortedIndices = selectedIndices.sorted()
        return sortedIndices.map { assets[$0] }
    }
}
