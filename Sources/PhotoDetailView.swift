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
    @State private var showControls = true          // 控制栏及导航栏是否显示
    @State private var dragOffset: CGFloat = 0      // 拖动偏移量
    @State private var isShuffle = false            // 是否随机播放
    
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
                        .offset(x: dragOffset)          // 跟随手指移动
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
                                    // 释放后弹回原位置
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dragOffset = 0
                                    }
                                }
                        )
                        .onTapGesture {
                            // 单击切换所有 UI 的显示/隐藏
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                } else {
                    ProgressView()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            
            // 底部控制栏（可隐藏，同时导航栏也会跟着隐藏）
            if showControls {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        // 随机播放按钮
                        Button(action: {
                            isShuffle.toggle()
                            // 如果正在播放，重置定时器以立即应用新模式
                            if isPlaying {
                                resetAutoPlay()
                            }
                        }) {
                            Image(systemName: "shuffle")
                                .font(.title3)
                                .symbolVariant(isShuffle ? .fill : .none)
                                .foregroundColor(isShuffle ? .yellow : .white)
                        }
                        
                        // 速度选择
                        Picker("速度", selection: $speed) {
                            Text("0.5秒").tag(0.5)
                            Text("1秒").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                        
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
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .background(.ultraThinMaterial)   // 毛玻璃背景
                }
            }
        }
        .navigationBarHidden(!showControls)   // 隐藏控制栏时同时隐藏导航栏（返回按钮消失）
        .onAppear {
            loadCurrentImage()
        }
        .onDisappear {
            stopAutoPlay()
        }
        .onChange(of: currentIndex) { _ in
            loadCurrentImage()
        }
        .onChange(of: speed) { _ in
            if isPlaying {
                resetAutoPlay()
            }
        }
        .onChange(of: isShuffle) { _ in
            if isPlaying {
                resetAutoPlay()
            }
        }
        .statusBar(hidden: !showControls)     // 状态栏也一起隐藏
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
    
    // MARK: - 手动翻页（始终顺序上下翻）
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
        if isPlaying {
            resetAutoPlay()
        }
    }
    
    // MARK: - 自动播放逻辑
    private func startAutoPlay() {
        guard !assets.isEmpty else { return }
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { _ in
            DispatchQueue.main.async {
                self.advanceAutoPlay()
            }
        }
    }
    
    private func stopAutoPlay() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }
    
    private func resetAutoPlay() {
        // 停止再按当前速度、模式重新开始
        stopAutoPlay()
        startAutoPlay()
    }
    
    private func advanceAutoPlay() {
        guard !assets.isEmpty else { return }
        if isShuffle {
            // 随机模式：随机跳到一张图，且不与当前相同（若图片数量>1）
            let count = assets.count
            if count > 1 {
                var randomIndex = Int.random(in: 0..<count)
                while randomIndex == currentIndex {
                    randomIndex = Int.random(in: 0..<count)
                }
                currentIndex = randomIndex
            }
            // 只有1张图时不做改变
        } else {
            // 顺序模式
            currentIndex = (currentIndex + 1) % assets.count
        }
    }
}
