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
    
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimatingSlide = false
    
    @State private var screenWidth: CGFloat = UIScreen.main.bounds.width
    
    init(assets: [PHAsset], initialIndex: Int) {
        self.assets = assets
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geo in
                ZStack {
                    // 上一张图
                    if let prevImage = prevImage, dragOffset > 0 {
                        Image(uiImage: prevImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .offset(x: dragOffset - geo.size.width)
                    }
                    
                    // 当前图
                    if let currentImage = currentImage {
                        Image(uiImage: currentImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .offset(x: dragOffset)
                    } else {
                        ProgressView()
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    
                    // 下一张图
                    if let nextImage = nextImage, dragOffset < 0 {
                        Image(uiImage: nextImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .offset(x: dragOffset + geo.size.width)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isAnimatingSlide else { return }
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            guard !isAnimatingSlide else { return }
                            let threshold: CGFloat = 80
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            
                            if dragOffset < -threshold || velocity < -100 {
                                slideToNext()
                            } else if dragOffset > threshold || velocity > 100 {
                                slideToPrevious()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
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
            loadImage(at: currentIndex, isCurrent: true)
            preloadNeighbors()
        }
        .onDisappear {
            stopAutoPlay()
        }
        .onChange(of: currentIndex) { _ in
            loadImage(at: currentIndex, isCurrent: true)
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
    
    // MARK: - 图片加载
    private func loadImage(at index: Int, isCurrent: Bool) {
        guard index >= 0, index < assets.count else { return }
        let asset = assets[index]
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        let size = CGSize(width: screenWidth * UIScreen.main.scale,
                          height: UIScreen.main.bounds.height * UIScreen.main.scale)
        manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    if isCurrent {
                        self.currentImage = image
                    }
                    if index == ((self.currentIndex + 1) % self.assets.count) {
                        self.nextImage = image
                    }
                    if index == ((self.currentIndex - 1 + self.assets.count) % self.assets.count) {
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
        loadImage(at: nextIdx, isCurrent: false)
        loadImage(at: prevIdx, isCurrent: false)
    }
    
    // MARK: - 手动滑动动画（修复闪烁版）
    private func slideToNext() {
        guard !isAnimatingSlide else { return }
        isAnimatingSlide = true
        
        // 动画：当前图滑出左侧，下一张图从右侧滑入
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            dragOffset = -screenWidth
        }
        
        // 动画完成后立刻交换图片，消除闪烁
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // 直接用预加载的下一张替换当前图
            if let next = nextImage {
                currentImage = next
            }
            // 更新索引
            currentIndex = (currentIndex + 1) % assets.count
            // 重置偏移
            dragOffset = 0
            isAnimatingSlide = false
            resetAutoPlayIfNeeded()
        }
    }
    
    private func slideToPrevious() {
        guard !isAnimatingSlide else { return }
        isAnimatingSlide = true
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            dragOffset = screenWidth
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // 直接用预加载的上一张替换当前图
            if let prev = prevImage {
                currentImage = prev
            }
            currentIndex = (currentIndex - 1 + assets.count) % assets.count
            dragOffset = 0
            isAnimatingSlide = false
            resetAutoPlayIfNeeded()
        }
    }
    
    // MARK: - 自动播放（无滑动效果）
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
