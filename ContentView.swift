import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @StateObject private var library = WallpaperLibrary()
    @State private var showingImporter = false
    @State private var searchText = ""
    @State private var filter: LibraryFilter = .all
    @State private var itemToDelete: WallpaperItem?
    @State private var videoSizes: [UUID: CGSize] = [:]   // 异步读取到的视频尺寸

    enum LibraryFilter: String, CaseIterable {
        case all = "全部壁纸", builtIn = "精选壁纸", personal = "我的上传"
    }

    private var filteredItems: [WallpaperItem] {
        library.items.filter { item in
            let matchesFilter = filter == .all || (filter == .builtIn && item.kind == .builtIn) || (filter == .personal && item.kind != .builtIn)
            return matchesFilter && (searchText.isEmpty || item.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            mainPanel
        }
        .background(Color(red: 0.055, green: 0.065, blue: 0.095))
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): library.importFiles(urls)
            case .failure(let error): library.statusMessage = "选择文件失败：\(error.localizedDescription)"
            }
        }
        .alert("删除这个壁纸？",
               isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }),
               presenting: itemToDelete) { item in
            Button("删除", role: .destructive) { library.delete(item) }
            Button("取消", role: .cancel) {}
        } message: { item in
            Text("“\(item.title)”会从图库和这台 Mac 的存储中永久删除，无法恢复。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 12) {
                // 侧边栏图标：渐变色方块 + 电视星星符号（纯代码绘制，不依赖 AppIcon 是否设置）
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lumi Wallpaper").font(.system(size: 16, weight: .bold))
                    Text("桌面灵感库").font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("你的空间").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.38)).padding(.leading, 12)
                sidebarButton("square.grid.2x2.fill", "壁纸图库", selected: filter == .all) { filter = .all }
                sidebarButton("sparkles", "精选壁纸", selected: filter == .builtIn) { filter = .builtIn }
                sidebarButton("photo.stack.fill", "我的上传", selected: filter == .personal) { filter = .personal }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("快速操作").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.38)).padding(.leading, 12)
                Button { showingImporter = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 17))
                        Text("上传照片 / 视频").font(.system(size: 13, weight: .semibold))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 13)
                        .background(LinearGradient(colors: [.blue.opacity(0.85), .purple.opacity(0.85)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain)
                Button { library.restoreDesktop() } label: {
                    Label("恢复原桌面", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 12)
                }.buttonStyle(.plain)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { Circle().fill(.green).frame(width: 6, height: 6); Text("本地图库已启用").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.62)) }
                Text("导入的文件会保存在这台 Mac 上").font(.system(size: 10)).foregroundStyle(.white.opacity(0.34)).fixedSize(horizontal: false, vertical: true)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
        }
        .padding(22).frame(width: 235).background(Color.white.opacity(0.018))
    }

    private func sidebarButton(_ icon: String, _ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 19)
                Text(title)
                Spacer()
                if selected { RoundedRectangle(cornerRadius: 2).fill(.cyan).frame(width: 3, height: 17) }
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .white : .white.opacity(0.58))
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(selected ? .white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("让桌面，成为你的风格").font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("挑选一张喜欢的壁纸，或把自己的照片和视频放进来。").font(.system(size: 12)).foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.42))
                    TextField("搜索壁纸", text: $searchText).textFieldStyle(.plain).frame(width: 145)
                }.padding(11).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                Button { showingImporter = true } label: {
                    Label("上传", systemImage: "plus").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 11)
                        .background(.white, in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(Color.black.opacity(0.85))
                }.buttonStyle(.plain)
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let selected = library.selectedItem {
                        featuredPreview(selected)
                        if selected.fileURL != nil { calibrationPanel(selected) }
                    } else {
                        uploadBanner
                    }
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(filter.rawValue).font(.system(size: 18, weight: .bold))
                            Text("\(filteredItems.count) 张壁纸 · 点击卡片查看预览").font(.system(size: 11)).foregroundStyle(.white.opacity(0.42))
                        }
                        Spacer()
                        Picker("分类", selection: $filter) {
                            ForEach(LibraryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).frame(width: 260)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 15)], spacing: 17) {
                        ForEach(filteredItems) { item in
                            WallpaperCard(item: item, selected: library.selectedID == item.id, active: library.activeID == item.id,
                                          onDelete: { itemToDelete = item }) {
                                library.selectedID = item.id
                            }
                        }
                    }
                    if filteredItems.isEmpty { uploadBanner.padding(.vertical, 20) }
                }.padding(.horizontal, 30).padding(.bottom, 28)
            }
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(.cyan)
                Text(library.statusMessage).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("LUMI · DESKTOP STUDIO").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(.white.opacity(0.25))
            }.padding(.horizontal, 30).padding(.vertical, 12).background(.black.opacity(0.12))
        }
    }

    // MARK: - 画面校准

    /// 素材本身的尺寸（图片 / 视频），用来在预览里还原真实比例。
    private func contentSize(for item: WallpaperItem) -> CGSize {
        guard let url = item.fileURL else { return CGSize(width: 16, height: 10) }
        if item.kind != .video, let img = ImageCache.image(for: item.thumbURL ?? url), img.size.width > 0 { return img.size }
        if item.kind == .video, let size = videoSizes[item.id] { return size }
        return CGSize(width: 16, height: 9)   // 视频尺寸读取完成前先用 16:9 占位
    }

    /// 异步读取视频画面尺寸（已考虑旋转），读完后预览会自动刷新。
    private func loadVideoSize(for item: WallpaperItem) async {
        guard item.kind == .video, let url = item.fileURL, videoSizes[item.id] == nil else { return }
        do {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let size = natural.applying(transform)
            let w = abs(size.width), h = abs(size.height)
            if w > 0, h > 0 { videoSizes[item.id] = CGSize(width: w, height: h) }
        } catch {
            // 读取失败就继续使用 16:9 占位
        }
    }

    private func calibrationPanel(_ item: WallpaperItem) -> some View {
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 16, height: 10)
        let modeBinding = Binding<WallpaperScaleMode>(
            get: { library.scaleMode },
            set: { library.scaleMode = $0; library.calibrationChanged() }
        )
        return HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                calibrationPreview(item, size: contentSize(for: item))
                    .aspectRatio(screenSize.width / screenSize.height, contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 1))
                Text("预览框 = 你的屏幕（\(Int(screenSize.width)) × \(Int(screenSize.height))）；框外的部分不会显示")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.38))
            }.frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("画面校准").font(.system(size: 13, weight: .bold))
                Picker("比例", selection: modeBinding) {
                    ForEach(WallpaperScaleMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                sliderRow("缩放", $library.zoom, 0.5...3, String(format: "%.2f×", library.zoom))
                sliderRow("水平位置", $library.offsetX, -0.5...0.5, String(format: "%+.0f%%", library.offsetX * 100))
                sliderRow("垂直位置", $library.offsetY, -0.5...0.5, String(format: "%+.0f%%", library.offsetY * 100))
                HStack(spacing: 9) {
                    Button { library.resetCalibration() } label: {
                        Label("重置", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                    Button { library.applySelected() } label: {
                        Label("应用校准", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                            .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }.frame(width: 245, alignment: .leading)
        }
        .padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.07), lineWidth: 1))
        .task(id: item.id) { await loadVideoSize(for: item) }
    }

    private func sliderRow(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title); Spacer(); Text(display).monospacedDigit()
            }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            Slider(value: value, in: range, onEditingChanged: { editing in
                if !editing { library.calibrationChanged() }   // 松开滑块后才真正应用到桌面
            })
        }
    }

    /// 用和真正设置壁纸时相同的算法，在预览框里实时显示效果。
    private func calibrationPreview(_ item: WallpaperItem, size cs: CGSize) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let base: (CGFloat, CGFloat) = {
                switch library.scaleMode {
                case .fill:    let k = max(w / cs.width, h / cs.height); return (k, k)
                case .fit:     let k = min(w / cs.width, h / cs.height); return (k, k)
                case .stretch: return (w / cs.width, h / cs.height)
                }
            }()
            let dw = cs.width * base.0 * library.zoom
            let dh = cs.height * base.1 * library.zoom
            ZStack {
                Color.black
                Group {
                    if item.kind != .video, let url = item.thumbURL ?? item.fileURL, let img = ImageCache.image(for: url) {
                        Image(nsImage: img).resizable()
                    } else {
                        WallpaperArtwork(item: item)   // 视频：用占位画面显示取景范围
                    }
                }
                .frame(width: dw, height: dh)
                .offset(x: library.offsetX * w, y: -library.offsetY * h)   // 向上为正
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }

    private var uploadBanner: some View {
        Button { showingImporter = true } label: {
            HStack(spacing: 18) {
                ZStack { RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.08)); Image(systemName: "arrow.up.doc.fill").font(.system(size: 25)).foregroundStyle(.cyan) }.frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text("把你的灵感加入图库").font(.system(size: 16, weight: .bold))
                    Text("支持常见图片与视频格式 · 自动保存在本机").font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                Text("选择文件").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }.padding(18).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func featuredPreview(_ item: WallpaperItem) -> some View {
        HStack(spacing: 22) {
            ZStack(alignment: .bottomLeading) {
                WallpaperArtwork(item: item).frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 16))
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom).clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: 18, weight: .bold))
                    Text(item.kind == .video ? "VIDEO · 视频预览" : item.kind == .image ? "YOUR COLLECTION · 我的上传" : "CURATED WALLPAPER · 精选壁纸")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(.white.opacity(0.7))
                }.padding(17)
                if item.kind == .video, let url = item.fileURL {
                    VideoPreview(url: url).frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 16)).opacity(0.98)
                }
            }.frame(maxWidth: .infinity).frame(height: 190)
            VStack(alignment: .leading, spacing: 12) {
                Text("桌面预览").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.48))
                Text(item.title).font(.system(size: 21, weight: .bold, design: .rounded))
                Text(item.kind == .video ? "已保存的视频，可在这里预览。" : "应用后会替换当前桌面壁纸。你可以随时恢复原来的桌面。")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 9) {
                    Button { library.applySelected() } label: {
                        Label(item.kind == .video ? "应用到桌面" : "设为桌面壁纸", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 13).padding(.vertical, 10)
                            .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                    Button { showingImporter = true } label: { Image(systemName: "plus").font(.system(size: 12, weight: .bold)).padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).help("上传更多照片或视频")
                }
            }.frame(width: 245, alignment: .leading).padding(.vertical, 4)
        }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 21)).overlay(RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}

struct WallpaperCard: View {
    let item: WallpaperItem
    let selected: Bool
    let active: Bool
    var onDelete: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    WallpaperArtwork(item: item).frame(height: 125).clipShape(RoundedRectangle(cornerRadius: 12))
                    if item.kind == .video { Image(systemName: "play.fill").font(.system(size: 12)).padding(8).background(.black.opacity(0.45), in: Circle()).padding(9).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing) }
                    if active { Text("使用中").font(.system(size: 9, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 5).background(.green.opacity(0.85), in: Capsule()).padding(9) }
                }
                HStack(spacing: 9) {
                    Image(systemName: item.symbol).font(.system(size: 14)).foregroundStyle(item.palette.first ?? .cyan).frame(width: 30, height: 30).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(item.kind == .builtIn ? "精选壁纸" : item.kind == .video ? "我的视频" : "我的照片").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan).font(.system(size: 16)) }
                }.padding(.top, 10).padding(.horizontal, 2).padding(.bottom, 2)
            }.padding(9).background(selected ? .cyan.opacity(0.09) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? .cyan.opacity(0.65) : .white.opacity(0.055), lineWidth: selected ? 1.2 : 1))
        }.buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            // 只有用户上传的内容才能删除，精选壁纸不显示垃圾桶
            if let onDelete, item.kind != .builtIn {
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.6), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("删除")
                .padding(.top, 17).padding(.trailing, 17)
            }
        }
    }
}

/// 图片缓存：卡片、预览、校准滑块拖动时会反复读取同一张图，缓存后就不会卡。
enum ImageCache {
    private static let cache = NSCache<NSURL, NSImage>()
    static func image(for url: URL) -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}

struct WallpaperArtwork: View {
    let item: WallpaperItem
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: item.palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.13)).frame(width: proxy.size.width * 0.78).blur(radius: 2).offset(x: proxy.size.width * 0.34, y: -proxy.size.height * 0.36)
                Circle().fill((item.palette.last ?? Color.white).opacity(0.38)).frame(width: proxy.size.width * 0.8).blur(radius: 12).offset(x: -proxy.size.width * 0.33, y: proxy.size.height * 0.38)
                Image(systemName: item.symbol).font(.system(size: min(proxy.size.width, proxy.size.height) * 0.37, weight: .ultraLight)).foregroundStyle(.white.opacity(0.8)).shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                if let url = item.thumbURL ?? (item.kind == .image ? item.fileURL : nil), let nsImage = ImageCache.image(for: url) {
                    Image(nsImage: nsImage).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                }
                if item.kind == .video {
                    Image(systemName: "waveform.path").font(.system(size: 30, weight: .light)).foregroundStyle(.white.opacity(0.65)).offset(y: 35)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
    }
}

struct VideoPreview: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        let player = AVPlayer(url: url)
        context.coordinator.player = player
        view.player = player
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.player?.pause()
            let player = AVPlayer(url: url)
            context.coordinator.url = url
            context.coordinator.player = player
            nsView.player = player
            player.play()
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        nsView.player = nil
    }

    final class Coordinator {
        var url: URL
        var player: AVPlayer?
        init(url: URL) {
            self.url = url
        }
    }
}

#Preview {
    ContentView()
}
