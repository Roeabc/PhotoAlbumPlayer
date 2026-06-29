import SwiftUI
import Photos

struct SchemeDetailView: View {
    @EnvironmentObject var schemeStore: SchemeStore
    @State var scheme: ImageScheme
    var isNewMerge: Bool = false   // 是否刚从合并生成，默认未保存
    
    @State private var assets: [PHAsset] = []           // 正常浏览时的图片（方案内的）
    @State private var allSourceAssets: [PHAsset] = []  // 编辑模式下来源相册的全部图片
    @State private var lastViewedID: String? = nil
    
    @State private var isEditingSelection = false
    @State private var selectedIndices: Set<Int> = []   // 编辑模式下在 allSourceAssets 中的选中索引
    @State private var startIndex: Int? = nil
    
    @State private var showSelectedPlayback = false
    @State private var showSaveDialog = false
    @State private var newName: String = ""
    
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]
    
    var body: some View {
        VStack(spacing: 0) {
            if isEditingSelection {
                selectionToolbar
            }
            photoGrid
        }
        .navigationTitle(scheme.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if isEditingSelection {
                        Button("保存更改") {
                            showSaveDialog = true
                        }
                    }
                    Button(isEditingSelection ? "完成" : "编辑") {
                        isEditingSelection.toggle()
                        if isEditingSelection {
                            // 进入编辑模式：加载来源相册全部图片
                            loadAllSourceAssets()
                            // 初始化选中状态为当前方案图片的索引
                            selectedIndices = Set(allSourceAssets.indices.filter { index in
                                scheme.imageIDs.contains(allSourceAssets[index].localIdentifier)
                            })
                        } else {
                            startIndex = nil
                        }
                    }
                }
            }
        }
        .alert("保存方案", isPresented: $showSaveDialog) {
            TextField("方案名称", text: $newName)
            Button("另存为新方案") {
                saveAsNew()
            }
            if !isNewMerge {
                Button("覆盖原方案") {
                    saveChanges(overwrite: true)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("为更改后的方案命名")
        }
        .onAppear {
            // 正常浏览时加载方案内的图片
            assets = scheme.fetchAssets()
        }
    }
    
    private func loadAllSourceAssets() {
        allSourceAssets = scheme.fetchAllAssetsFromSourceAlbums()
    }
    
    // 编辑模式工具栏
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
            Button("全选") {
                selectedIndices = Set(0..<allSourceAssets.count)
            }
            Button("取消全选") {
                selectedIndices = []
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // 网格
    private var photoGrid: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    if isEditingSelection {
                        ForEach(Array(allSourceAssets.enumerated()), id: \.element.localIdentifier) { index, asset in
                            gridCell(index: index, asset: asset)
                                .id(asset.localIdentifier)
                        }
                    } else {
                        ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                            NavigationLink(destination: PhotoDetailView(
                                assets: assets,
                                initialIndex: index,
                                lastViewedID: $lastViewedID
                            )) {
                                PhotoCell(asset: asset)
                            }
                            .id(asset.localIdentifier)
                        }
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
            PhotoCell(asset: asset)
                .overlay(
                    isEditingSelection && selectedIndices.contains(index) ?
                    Rectangle().stroke(Color.blue, lineWidth: 3) : nil
                )
                .overlay(
                    isEditingSelection && selectedIndices.contains(index) ?
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .padding(4)
                        }
                        Spacer()
                    } : nil
                )
        }
        .onTapGesture {
            if isEditingSelection {
                handleSelectionTap(index: index)
            }
        }
    }
    
    @ViewBuilder
    private var selectedPlaybackLink: some View {
        if isEditingSelection && !selectedIndices.isEmpty {
            let selectedAssets = selectedIndices.sorted().map { allSourceAssets[$0] }
            NavigationLink(
                destination: PhotoDetailView(assets: selectedAssets, initialIndex: 0, lastViewedID: $lastViewedID),
                isActive: $showSelectedPlayback,
                label: { EmptyView() }
            )
            .hidden()
        }
    }
    
    // 选择逻辑：范围统一反转（同之前逻辑）
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
    
    // 保存
    private func saveAsNew() {
        let name = newName.isEmpty ? scheme.name + " 副本" : newName
        let newIDs = selectedIndices.sorted().map { allSourceAssets[$0].localIdentifier }
        // 另存为新方案，来源相册保持不变
        schemeStore.addScheme(name: name, imageIDs: newIDs, sourceAlbumIDs: scheme.sourceAlbumIDs)
        newName = ""
    }
    
    private func saveChanges(overwrite: Bool) {
        let newIDs = selectedIndices.sorted().map { allSourceAssets[$0].localIdentifier }
        if overwrite {
            var updated = scheme
            updated.name = newName.isEmpty ? scheme.name : newName
            updated.imageIDs = newIDs
            // 来源相册不变
            schemeStore.updateScheme(updated)
            scheme = updated
            assets = updated.fetchAssets()  // 刷新浏览状态
        } else {
            saveAsNew()
        }
        newName = ""
    }
}