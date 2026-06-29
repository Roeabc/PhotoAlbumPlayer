import SwiftUI
import Photos

struct SchemeDetailView: View {
    @EnvironmentObject var schemeStore: SchemeStore
    @State var scheme: ImageScheme
    var isNewMerge: Bool = false   // 是否刚从合并生成，默认未保存
    
    @State private var assets: [PHAsset] = []
    @State private var lastViewedID: String? = nil
    
    // 选择编辑
    @State private var isEditingSelection = false
    @State private var selectedIndices: Set<Int> = []
    @State private var startIndex: Int? = nil
    
    // 展示播放选中
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
                        if !isEditingSelection {
                            // 退出编辑模式时重置选择状态
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
            assets = scheme.fetchAssets()
            // 初始化选择状态为所有已存在图片（编辑模式时默认全选）
            if isEditingSelection {
                selectedIndices = Set(0..<assets.count)
            }
        }
    }
    
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
                selectedIndices = Set(0..<assets.count)
            }
            Button("取消全选") {
                selectedIndices = []
            }
        }
        .padding()
        .background(.ultraThinMaterial)
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
            if isEditingSelection {
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
    
    // 同相册选图逻辑：范围统一反转
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
    
    // 保存：另存或覆盖
    private func saveAsNew() {
        let name = newName.isEmpty ? scheme.name + " 副本" : newName
        let newIDs = selectedIndices.sorted().compactMap { index -> String? in
            guard index < assets.count else { return nil }
            return assets[index].localIdentifier
        }
        schemeStore.addScheme(name: name, imageIDs: newIDs)
        newName = ""
    }
    
    private func saveChanges(overwrite: Bool) {
        let newIDs = selectedIndices.sorted().compactMap { index -> String? in
            guard index < assets.count else { return nil }
            return assets[index].localIdentifier
        }
        if overwrite {
            var updated = scheme
            updated.name = newName.isEmpty ? scheme.name : newName
            updated.imageIDs = newIDs
            schemeStore.updateScheme(updated)
            // 刷新当前界面
            scheme = updated
            assets = updated.fetchAssets()
        } else {
            saveAsNew()
        }
        newName = ""
    }
}