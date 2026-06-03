import SwiftUI
import Photos

struct PhotoDetailView: View {
    let assets: [PHAsset]
    let initialIndex: Int
    
    @State private var currentIndex: Int
    @State private var currentImage: UIImage? = nil
    
    @State private var preloadedImages: [String: UIImage] = [:]
    
    @State private var isPlaying = false
    @State private var speed: TimeInterval = 0.5
    @State private var timer: Timer? = nil
    @State private var showControls = true
    @State private var isShuffle = false
    
    // 随机播放洗牌队列
    @State private var shuffleQueue: [Int] = []
    
    // 跨轮防重复：上一轮最后 20 张的索引（作为新轮开头禁止的索引）
    @State private var forbiddenHeadIndices: [Int] = []
    // 当前轮最近播放的索引（用于在轮结束时记录尾部）
    @State private var recentAutoPlayedIndices: [Int] = []
    
    private let screenWidth: CGFloat = UIScreen.main.bounds.width
    private let screenHeight: CGFloat = UIScreen.main.bounds.height
    private let scale: CGFloat = UIScreen.main.scale
    
    private var fullSize: CGSize {
        CGSize(width: screenWidth * scale, height: screenHeight * scale)
    }
    
    private let neighborCount = 3
    private let shufflePreloadCount = 3
    private let tailHeadRestriction = 20   // 结尾/开头各 20 张
    
    init(assets: [PHAsset], initialIndex: Int) {
        self.assets = assets
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geo in
                if let currentImage = currentImage {
                    Image(uiImage: currentImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    ProgressView()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { _ in }
                    .onEnded { value in
                        let threshold: CGFloat = 80
                        let velocity = value.predictedEndTranslation.width - value.translation.width
                        if value.translation.width < -threshold || velocity < -100 {
                            goToNext()
                        } else if value.translation.width > threshold || velocity > 100 {
                            goToPrevious()
                        }
                    }
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
            }
            
            if showControls {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Button(action: {
                            isShuffle.toggle()
                            if isPlaying { resetAutoPlay() }
                        }) {
                            Image(systemName: "shuffle")
                                .font(.title3)
                                .symbolVariant(isShuffle ? .fill : .none)
                                .foregroundColor(isShuffle ? .yellow : .white)
                        }
                        
                        Picker("速度", selection: $speed) {
                            Text("0.5秒").tag(0.5)
                            Text("1秒").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                        
                        Spacer()
                        
                        Button(action: {
                            isPlaying ? stopAutoPlay() : startAutoPlay()
                        }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 36))
                        }
                        
                        Spacer()
                        
                        Text("\(currentIndex + 1) / \(assets.count)")
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .navigationBarHidden(!showControls)
        .onAppear {
            loadAndCache(asset: assets[currentIndex]) { image in
                if let image = image { self.currentImage = image }
            }
            preloadNeighbors()
            if isShuffle { buildShuffleQueue() }
        }
        .onDisappear { stopAutoPlay() }
        .onChange(of: currentIndex) { _ in
            let asset = assets[currentIndex]
            if let cached = preloadedImages[asset.localIdentifier] {
                currentImage = cached
            } else {
                loadAndCache(asset: asset) { image in
                    if let image = image { self.currentImage = image }
                }
            }
            preloadNeighbors()
            if isShuffle { preloadShuffleNext() }
        }
        .onChange(of: speed) { _ in
            if isPlaying { resetAutoPlay() }
        }
        .onChange(of: isShuffle) { _ in
            if isPlaying { resetAutoPlay() }
        }
        .statusBar(hidden: !showControls)
    }
    
    // MARK: - 图片加载
    private func loadAndCache(asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false
        manager.requestImage(for: asset,
                             targetSize: fullSize,
                             contentMode: .aspectFit,
                             options: options) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.preloadedImages[asset.localIdentifier] = image
                    completion(image)
                }
            } else {
                completion(nil)
            }
        }
    }
    
    private func preloadNeighbors() {
        guard !assets.isEmpty else { return }
        let count = assets.count
        for offset in 1...neighborCount {
            let nextIdx = (currentIndex + offset) % count
            let prevIdx = (currentIndex - offset + count) % count
            let nextAsset = assets[nextIdx]
            let prevAsset = assets[prevIdx]
            if preloadedImages[nextAsset.localIdentifier] == nil {
                loadAndCache(asset: nextAsset) { _ in }
            }
            if preloadedImages[prevAsset.localIdentifier] == nil {
                loadAndCache(asset: prevAsset) { _ in }
            }
        }
    }
    
    // MARK: - 随机播放核心（带跨轮防重复）
    private func buildShuffleQueue() {
        let count = assets.count
        guard count > 1 else {
            shuffleQueue = []
            return
        }
        
        // 候选池：除当前图外的所有索引
        var pool = Array(0..<count)
        pool.removeAll { $0 == currentIndex }
        
        // 如果需要跨轮防重复（相册 > 40 张）且 forbiddenHeadIndices 不为空
        let applyRestriction = count > tailHeadRestriction * 2 && !forbiddenHeadIndices.isEmpty
        
        if applyRestriction {
            // 从池中选出 20 个不在禁止列表中的索引，放到队列头部
            var safePool = pool.filter { !forbiddenHeadIndices.contains($0) }
            // 如果 safePool 数量不足 20（极少情况，如池子太小），降级为普通随机
            if safePool.count >= tailHeadRestriction {
                safePool.shuffle()
                let head = Array(safePool.prefix(tailHeadRestriction))
                // 剩余的索引（包括那些在禁止列表中的）
                var remaining = pool.filter { !head.contains($0) }
                remaining.shuffle()
                shuffleQueue = head + remaining
            } else {
                // 安全池不够 20 个，放弃限制
                pool.shuffle()
                shuffleQueue = pool
            }
        } else {
            // 正常洗牌
            pool.shuffle()
            shuffleQueue = pool
        }
        
        // 预加载队列前几张
        preloadShuffleNext()
    }
    
    private func preloadShuffleNext() {
        guard isShuffle else { return }
        let preloadCount = min(shufflePreloadCount, shuffleQueue.count)
        for i in 0..<preloadCount {
            let idx = shuffleQueue[i]
            let asset = assets[idx]
            if preloadedImages[asset.localIdentifier] == nil {
                loadAndCache(asset: asset) { _ in }
            }
        }
    }
    
    // MARK: - 手动翻页（始终顺序）
    private func goToNext() {
        guard !assets.isEmpty else { return }
        currentIndex = (currentIndex + 1) % assets.count
        resetAutoPlayIfNeeded()
    }
    
    private func goToPrevious() {
        guard !assets.isEmpty else { return }
        currentIndex = (currentIndex - 1 + assets.count) % assets.count
        resetAutoPlayIfNeeded()
    }
    
    // MARK: - 自动播放控制
    private func startAutoPlay() {
        guard !assets.isEmpty else { return }
        isPlaying = true
        
        // 重置跨轮限制（手动触发播放 / 手动翻页后都算新开始）
        forbiddenHeadIndices = []
        recentAutoPlayedIndices = []
        
        if isShuffle {
            buildShuffleQueue()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { _ in
            DispatchQueue.main.async { advanceAutoPlay() }
        }
    }
    
    private func stopAutoPlay() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }
    
    private func resetAutoPlay() {
        stopAutoPlay()
        startAutoPlay()
    }
    
    private func resetAutoPlayIfNeeded() {
        if isPlaying { resetAutoPlay() }
    }
    
    // MARK: - 自动播放推进（顺序 / 洗牌）
    private func advanceAutoPlay() {
        guard !assets.isEmpty else { return }
        let count = assets.count
        
        if isShuffle {
            // 队列空 → 一轮结束，记录尾部，生成新一轮
            if shuffleQueue.isEmpty {
                // 保存当前轮的最近 20 张作为下一轮的禁止开头
                forbiddenHeadIndices = recentAutoPlayedIndices
                recentAutoPlayedIndices = []
                buildShuffleQueue()
            }
            
            guard !shuffleQueue.isEmpty else { return }
            
            let nextIdx = shuffleQueue.removeFirst()
            let nextAsset = assets[nextIdx]
            
            if let cachedImage = preloadedImages[nextAsset.localIdentifier] {
                currentImage = cachedImage
                currentIndex = nextIdx
            } else {
                currentIndex = nextIdx
            }
            
            // 记录最近播放（用于计算轮尾）
            recentAutoPlayedIndices.append(nextIdx)
            if recentAutoPlayedIndices.count > tailHeadRestriction {
                recentAutoPlayedIndices.removeFirst()
            }
            
            preloadShuffleNext()
            
        } else {
            // 顺序播放
            let nextIdx = (currentIndex + 1) % count
            let nextAsset = assets[nextIdx]
            if let cachedNext = preloadedImages[nextAsset.localIdentifier] {
                currentImage = cachedNext
                currentIndex = nextIdx
            } else {
                currentIndex = nextIdx
            }
        }
    }
}