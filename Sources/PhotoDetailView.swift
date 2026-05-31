import SwiftUI
import Photos

struct PhotoDetailView: View {
    let assets: [PHAsset]
    let initialIndex: Int
    
    @State private var currentIndex: Int
    @State private var currentImage: UIImage? = nil
    
    // 预加载缓存：key = asset.localIdentifier
    @State private var preloadedImages: [String: UIImage] = [:]
    
    @State private var isPlaying = false
    @State private var speed: TimeInterval = 0.5
    @State private var timer: Timer? = nil
    @State private var showControls = true
    @State private var isShuffle = false
    
    // 随机播放的未来索引队列（真随机，预加载3张）
    @State private var upcomingRandomIndices: [Int] = []
    
    private let screenWidth: CGFloat = UIScreen.main.bounds.width
    private let screenHeight: CGFloat = UIScreen.main.bounds.height
    private let scale: CGFloat = UIScreen.main.scale
    
    // 统一使用高清尺寸进行预加载
    private var fullSize: CGSize {
        CGSize(width: screenWidth * scale, height: screenHeight * scale)
    }
    
    // 预加载数量配置：前后各 3 张高清原图
    private let forwardPreloadCount = 3
    private let backwardPreloadCount = 3
    
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
                if let image = image {
                    self.currentImage = image
                }
            }
            preloadAroundCurrent()
        }
        .onDisappear {
            stopAutoPlay()
        }
        .onChange(of: currentIndex) { _ in
            let asset = assets[currentIndex]
            if let cached = preloadedImages[asset.localIdentifier] {
                currentImage = cached
            } else {
                loadAndCache(asset: asset) { image in
                    if let image = image {
                        self.currentImage = image
                    }
                }
            }
            preloadAroundCurrent()
            // 如果是随机模式，确保队列充足
            if isShuffle {
                ensureRandomQueue()
            }
        }
        .onChange(of: speed) { _ in
            if isPlaying { resetAutoPlay() }
        }
        .onChange(of: isShuffle) { _ in
            if isPlaying { resetAutoPlay() }
        }
        .statusBar(hidden: !showControls)
    }
    
    // MARK: - 图片加载与缓存
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
    
    private func preloadAroundCurrent() {
        guard !assets.isEmpty else { return }
        let count = assets.count
        
        // 向前预加载（未来方向）
        for offset in 1...forwardPreloadCount {
            let nextIdx = (currentIndex + offset) % count
            let asset = assets[nextIdx]
            if preloadedImages[asset.localIdentifier] == nil {
                loadAndCache(asset: asset) { _ in }
            }
        }
        
        // 向后预加载（历史方向）
        for offset in 1...backwardPreloadCount {
            let prevIdx = (currentIndex - offset + count) % count
            let asset = assets[prevIdx]
            if preloadedImages[asset.localIdentifier] == nil {
                loadAndCache(asset: asset) { _ in }
            }
        }
    }
    
    // MARK: - 随机队列管理
    private func ensureRandomQueue() {
        guard !assets.isEmpty, isShuffle else { return }
        let count = assets.count
        
        // 如果相册只有1张图，随机无意义
        guard count > 1 else {
            upcomingRandomIndices = []
            return
        }
        
        // 补充队列至3个
        while upcomingRandomIndices.count < 3 {
            var rand = Int.random(in: 0..<count)
            // 避免与当前索引及队列中已有索引重复
            let forbidden = [currentIndex] + upcomingRandomIndices
            while forbidden.contains(rand) {
                rand = Int.random(in: 0..<count)
            }
            upcomingRandomIndices.append(rand)
            // 预加载这个随机索引的高清图
            let asset = assets[rand]
            if preloadedImages[asset.localIdentifier] == nil {
                loadAndCache(asset: asset) { _ in }
            }
        }
    }
    
    // MARK: - 手动翻页
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
    
    // MARK: - 自动播放（高清无卡顿）
    private func startAutoPlay() {
        guard !assets.isEmpty else { return }
        isPlaying = true
        
        // 随机模式下清空旧队列，重新生成真随机序列
        if isShuffle {
            upcomingRandomIndices.removeAll()
            ensureRandomQueue()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { _ in
            DispatchQueue.main.async {
                advanceAutoPlay()
            }
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
    
    private func advanceAutoPlay() {
        guard !assets.isEmpty else { return }
        let count = assets.count
        
        if isShuffle {
            // 确保队列至少有1个准备好的索引
            if upcomingRandomIndices.isEmpty {
                ensureRandomQueue()
            }
            
            guard !upcomingRandomIndices.isEmpty else {
                // 极端情况：队列仍为空（比如只有1张图），直接跳过
                return
            }
            
            // 取出队列第一个随机索引
            let nextRandomIndex = upcomingRandomIndices.removeFirst()
            let nextAsset = assets[nextRandomIndex]
            
            if let cachedImage = preloadedImages[nextAsset.localIdentifier] {
                // 直接显示预加载好的高清图
                currentImage = cachedImage
                currentIndex = nextRandomIndex
            } else {
                // 万一缓存没有，降级处理（概率极低）
                currentIndex = nextRandomIndex
            }
            
            // 补充队列，并预加载新的随机高清图
            ensureRandomQueue()
            
        } else {
            // 顺序模式：直接取下一张
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
