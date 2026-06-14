import SwiftUI
import Photos

struct PhotoDetailView: View {
    let assets: [PHAsset]
    let initialIndex: Int
    @Binding var lastViewedID: String?   // 回传最后浏览图片的 ID
    
    @State private var currentIndex: Int
    @State private var currentImage: UIImage? = nil
    
    @State private var preloadedImages: [String: UIImage] = [:]
    
    @State private var isPlaying = false
    @State private var speed: TimeInterval = 0.5
    @State private var timer: Timer? = nil
    @State private var showControls = true
    @State private var isShuffle = false
    
    @State private var shuffleQueue: [Int] = []
    @State private var forbiddenHeadIndices: [Int] = []
    @State private var recentAutoPlayedIndices: [Int] = []
    
    private let screenWidth: CGFloat = UIScreen.main.bounds.width
    private let screenHeight: CGFloat = UIScreen.main.bounds.height
    private let scale: CGFloat = UIScreen.main.scale
    
    private var fullSize: CGSize {
        CGSize(width: screenWidth * scale, height: screenHeight * scale)
    }
    
    private let neighborCount = 3
    private let shufflePreloadCount = 3
    private let tailHeadRestriction = 20
    
    init(assets: [PHAsset], initialIndex: Int, lastViewedID: Binding<String?>) {
        self.assets = assets
        self.initialIndex = initialIndex
        self._lastViewedID = lastViewedID
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
        .onDisappear {
            stopAutoPlay()
            // 返回前记录最后浏览的图片 ID
            if currentIndex < assets.count {
                lastViewedID = assets[currentIndex].localIdentifier
            }
        }
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
    
    private func loadAndCache(asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false
        manager.requestImage(for: asset, targetSize: fullSize, contentMode: .aspectFit, options: options) { image, _ in
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
    
    private func buildShuffleQueue() {
        let count = assets.count
        guard count > 1 else {
            shuffleQueue = []
            return
        }
        var pool = Array(0..<count)
        pool.removeAll { $0 == currentIndex }
        let applyRestriction = count > tailHeadRestriction * 2 && !forbiddenHeadIndices.isEmpty
        if applyRestriction {
            var safePool = pool.filter { !forbiddenHeadIndices.contains($0) }
            if safePool.count >= tailHeadRestriction {
                safePool.shuffle()
                let head = Array(safePool.prefix(tailHeadRestriction))
                var remaining = pool.filter { !head.contains($0) }
                remaining.shuffle()
                shuffleQueue = head + remaining
            } else {
                pool.shuffle()
                shuffleQueue = pool
            }
        } else {
            pool.shuffle()
            shuffleQueue = pool
        }
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
    
    private func startAutoPlay() {
        guard !assets.isEmpty else { return }
        isPlaying = true
        forbiddenHeadIndices = []
        recentAutoPlayedIndices = []
        if isShuffle { buildShuffleQueue() }
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
    
    private func advanceAutoPlay() {
        guard !assets.isEmpty else { return }
        let count = assets.count
        
        if isShuffle {
            if shuffleQueue.isEmpty {
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
            recentAutoPlayedIndices.append(nextIdx)
            if recentAutoPlayedIndices.count > tailHeadRestriction {
                recentAutoPlayedIndices.removeFirst()
            }
            preloadShuffleNext()
        } else {
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
