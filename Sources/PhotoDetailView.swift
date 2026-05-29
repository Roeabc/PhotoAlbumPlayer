import SwiftUI
import Photos

struct PhotoDetailView: View {
    let assets: [PHAsset]
    let initialIndex: Int
    
    @State private var currentIndex: Int
    @State private var fullImage: UIImage? = nil
    @State private var isPlaying = false
    @State private var speed: TimeInterval = 0.5
    @State private var timer: Timer? = nil
    @State private var showControls = true          // 控制栏是否显示
    @State private var dragOffset: CGFloat = 0      // 手势拖动偏移量（用于动画）
    
    init(assets: [PHAsset], initialIndex: Int) {
        self.assets = assets
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            // 图片展示区域（全屏）
            GeometryReader { geo in
                if let fullImage = fullImage {
                    Image(uiImage: fullImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .offset(x: dragOffset)          // 拖动偏移
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation.width
                                }
                                .onEnded { value in
                                    let threshold: CGFloat = 50
                                    if value.translation.width < -threshold {
                                        // 向左滑动，下一张
                                        goToNext()
                                    } else if value.translation.width > threshold {
                                        // 向右滑动，上一张
                                        goToPrevious()
                                    }
                                    // 恢复偏移
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dragOffset = 0
                                    }
                                }
                        )
                        .onTapGesture {
                            // 单击屏幕切换控制栏显示/隐藏
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                } else {
                    ProgressView()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            
            // 底部控制栏（可隐藏）
            if showControls {
                VStack {
                    Spacer()
                    HStack {
                        // 速度选择
                        Picker("速度", selection: $speed) {
                            Text("0.5秒").tag(0.5)
                            Text("1秒").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                        
                        Spacer()
                        
                        // 播放/暂停按钮
                        Button(action: {
                            if isPlaying {
                                stopAutoPlay()
                            } else {
                                startAutoPlay()
                            }
                        }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 36))
                        }
                        
                        Spacer()
                        
                        // 图片序号
                        Text("\(currentIndex + 1) / \(assets.count)")
                            .monospacedDigit()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .background(.ultraThinMaterial)   // 毛玻璃背景，便于看清
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCurrentImage()
        }
        .onDisappear {
            stopAutoPlay()
        }
        .onChange(of: currentIndex) { _ in
            loadCurrentImage()
        }
        .onChange(of: speed) { newSpeed in
            if isPlaying {
                stopAutoPlay()
                startAutoPlay()
            }
        }
        .statusBar(hidden: !showControls)   // 隐藏控制栏时也隐藏状态栏，更沉浸
    }
    
    // MARK: - 图片加载
    private func loadCurrentImage() {
        guard currentIndex >= 0, currentIndex < assets.count else { return }
        let asset = assets[currentIndex]
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(width: screenSize.width * UIScreen.main.scale,
                                height: screenSize.height * UIScreen.main.scale)
        manager.requestImage(for: asset,
                             targetSize: targetSize,
                             contentMode: .aspectFit,
                             options: options) { image, _ in
            DispatchQueue.main.async {
                self.fullImage = image
            }
        }
    }
    
    // MARK: - 翻页逻辑（手动 + 自动共用）
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
    
    private func resetAutoPlayIfNeeded() {
        // 如果正在自动播放，重置定时器，让间隔从头计时
        if isPlaying {
            stopAutoPlay()
            startAutoPlay()
        }
    }
    
    // MARK: - 自动播放控制
    private func startAutoPlay() {
        guard !assets.isEmpty else { return }
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { _ in
            DispatchQueue.main.async {
                self.currentIndex = (self.currentIndex + 1) % self.assets.count
            }
        }
    }
    
    private func stopAutoPlay() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }
}
