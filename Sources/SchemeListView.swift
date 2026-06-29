import SwiftUI

struct SchemeListView: View {
    @EnvironmentObject var schemeStore: SchemeStore
    @State private var selectMode = false       // 合并选择模式
    @State private var selectedSchemes: Set<UUID> = []
    @State private var showMergeResult = false
    @State private var mergedScheme: ImageScheme? = nil
    
    var body: some View {
        List {
            if selectMode {
                Section(header: Text("选择要合并的方案")) {
                    ForEach(schemeStore.schemes) { scheme in
                        HStack {
                            Image(systemName: selectedSchemes.contains(scheme.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(scheme.name)
                                    .font(.headline)
                                Text("\(scheme.imageIDs.count) 张图片")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedSchemes.contains(scheme.id) {
                                selectedSchemes.remove(scheme.id)
                            } else {
                                selectedSchemes.insert(scheme.id)
                            }
                        }
                    }
                }
                
                if !selectedSchemes.isEmpty {
                    Button("合并选中的 \(selectedSchemes.count) 个方案") {
                        let schemes = schemeStore.schemes.filter { selectedSchemes.contains($0.id) }
                        mergedScheme = schemeStore.mergeSchemes(schemes, name: "合并方案")
                        showMergeResult = true
                    }
                }
                
                Button("取消") {
                    selectMode = false
                    selectedSchemes = []
                }
            } else {
                ForEach(schemeStore.schemes) { scheme in
                    NavigationLink(destination: SchemeDetailView(scheme: scheme)) {
                        VStack(alignment: .leading) {
                            Text(scheme.name)
                                .font(.headline)
                            Text("\(scheme.imageIDs.count) 张图片 · 创建于 \(scheme.creationDate.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        schemeStore.deleteScheme(schemeStore.schemes[index])
                    }
                }
            }
        }
        .navigationTitle("收藏方案")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(selectMode ? "完成" : "合并") {
                    selectMode.toggle()
                    if !selectMode {
                        selectedSchemes = []
                    }
                }
            }
        }
        .sheet(isPresented: $showMergeResult) {
            if let mergedScheme = mergedScheme {
                NavigationView {
                    SchemeDetailView(scheme: mergedScheme, isNewMerge: true)
                }
            }
        }
    }
}