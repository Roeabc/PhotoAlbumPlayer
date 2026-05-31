import SwiftUI
import Photos

struct PhotoDetailView: View {
    let assets: [PHAsset]
    let initialIndex: Int
    
    @State private var currentIndex: Int
    @State private var currentImage: UIImage? = nil
    @State private var nextImage: UIImage? = nil
    @State private var prevImage: UIImage? = nil
    
    @State private var isPlaying = false
    @State private var speed: TimeInterval = 0.5
    @State private var timer: Timer? = nil
    @State private var showControls = true
    @State private var isShuffle = false
    
    private let screenWidth: CGFloat = UIScreen.main.bounds.width
    private let screenHeight: CGFloat = UIScreen.main.bounds.height
    private let scale: CGFloat = UIScreen.main.scale
    
    // 当前显示用全尺寸（屏幕点对点，保证清晰）
    private var fullSize: CGSize {
        CGSize(width: screenWidth * scale, height: screenHeight * scale)
    }
    
    // 邻居预加载用小尺寸（速度快，不影响清晰度）
    private var thumbSize: CGSize {
        CGSize(width: screenWidth * scale / 3, height: screenHeight * scale / 3)
    }
    
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
            loadImage(at: currentIndex, targetSize: fullSize, isCurrent: true)
            preloadNeighbors()
        }
        .onDisappear {
            stopAutoPlay()
        }
        .onChange(of: currentIndex) { _ in
            loadImage(at: currentIndex, targetSize: fullSize, isCurrent: true)
            preloadNeighbors()
        }
        .onChange(of: speed) { _ in
            if isPlaying { resetAutoPlay() }
        }
        .onChange(of: isShuffle) { _ in
            if isPlaying { resetAutoPlay() }
        }
        .statusBar(hidden: !showControls)
    }
    
    // MARK: - 图片加载（当前图高清，邻居图快速）
    private func loadImage(at index: Int, targetSize: CGSize, isCurrent: Bool) {
        guard index >= 0, index < assets.count else { return }
        let asset = assets[index]
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        
        // 当前显示的大图使用高质量模式，保证清晰
        if isCurrent {
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
        } else {
            // 预加载邻居图使用快速模式
            options.deliveryMode = .fastFormat
        }
        
        options.isSynchronous = false
        
        manager.requestImage(for: asset,
                             targetSize: targetSize,
                             contentMode: .aspectFit,
                             options: options) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    if isCurrent {
                        self.currentImage = image
                    }
                    // 更新邻居缓存
                    let count = self.assets.count
                    let nextIdx = (self.currentIndex + 1) % count
                    let prevIdx = (self.currentIndex - 1 + count) % count
                    if index == nextIdx {
                        self.nextImage = image
                    }
                    if index == prevIdx {
                        self.prevImage = image
                    }
                }
            }
        }
    }
    
    private func preloadNeighbors() {
        guard !assets.isEmpty else { return }
        let count = assets.count
        let nextIdx = (currentIndex + 1) % count
        let prevIdx = (currentIndex - 1 + count) % count
        loadImage(at: nextIdx, targetSize: thumbSize, isCurrent: false)
        loadImage(at: prevIdx, targetSize: thumbSize, isCurrent: false)
    }
    
    // MARK: - 手动翻页（无动画，直接切换）
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
    
    // MARK: - 自动播放（无特效）
    private func startAutoPlay() {
        guard !assets.isEmpty else { return }
        isPlaying = true
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
        if isShuffle {
            let count = assets.count
            if count > 1 {
                var randomIndex = Int.random(in: 0..<count)
                while randomIndex == currentIndex {
                    randomIndex = Int.random(in: 0..<count)
                }
                currentIndex = randomIndex
            }
        } else {
            currentIndex = (currentIndex + 1) % assets.count
        }
    }
}
