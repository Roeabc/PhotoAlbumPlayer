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
    
    init(assets: [PHAsset], initialIndex: Int) {
        self.assets = assets
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        VStack {
            GeometryReader { geo in
                if let fullImage = fullImage {
                    Image(uiImage: fullImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    ProgressView()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            
            HStack {
                Picker("速度", selection: $speed) {
                    Text("0.5秒").tag(0.5)
                    Text("1秒").tag(1.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                
                Spacer()
                
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
                
                Text("\(currentIndex + 1) / \(assets.count)")
                    .monospacedDigit()
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
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
    }
    
    private func loadCurrentImage() {
        guard currentIndex < assets.count else { return }
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