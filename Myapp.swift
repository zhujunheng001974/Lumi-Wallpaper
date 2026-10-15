import SwiftUI
import Combine
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// 界面语言：中文 / English（存在 UserDefaults 里，默认中文）
enum AppLanguage {
    static let key = "Lumi.language"
    static var isEnglish: Bool { UserDefaults.standard.string(forKey: key) == "en" }
}

/// 按当前语言返回中文或英文文案
func tr(_ zh: String, _ en: String) -> String { AppLanguage.isEnglish ? en : zh }

/// 分类名（内部一律用中文做 key，显示时再翻译）
func localizedCategory(_ zh: String) -> String {
    guard AppLanguage.isEnglish else { return zh }
    switch zh {
    case "少女系": return "Girly"
    case "深色科技": return "Dark Tech"
    case "风景渐变": return "Scenic Gradients"
    case "精选": return "Featured"
    default: return zh
    }
}

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1220, height: 800)
    }
}

/// 画面比例模式
enum WallpaperScaleMode: String, CaseIterable, Identifiable {
    case fill      // 自动填充：保持比例铺满屏幕，超出部分裁切
    case fit       // 完整显示：保持比例完整显示，四周留黑边
    case stretch   // 拉伸：直接拉伸到屏幕大小（会变形）

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fill: return tr("自动填充", "Fill")
        case .fit: return tr("完整显示", "Fit")
        case .stretch: return tr("拉伸", "Stretch")
        }
    }
}

/// 画面校准参数。offsetX / offsetY 以屏幕宽/高的比例表示，向右、向上为正。
struct WallpaperCalibration: Equatable {
    var mode: WallpaperScaleMode = .fill
    var zoom: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0
    /// 是否有手动缩放/位移（有的话静态壁纸需要自己渲染裁切后的图片）
    var hasManualAdjust: Bool { zoom != 1 || offsetX != 0 || offsetY != 0 }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 视频壁纸窗口和同步桌面用的透明窗口也算"可见窗口"，所以 flag 可能一直是 true；
        // 这里只看真正的主窗口（能成为 main 的窗口）是否可见。
        let mainVisible = sender.windows.contains { $0.canBecomeMain && $0.isVisible && !$0.isMiniaturized }
        if !mainVisible {
            for window in sender.windows where window.canBecomeMain {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
                break
            }
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}

extension Color {
    /// 用 0xRRGGBB 创建颜色
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// 第 21 张之后的精选壁纸（wall_21 ~ wall_100），按顺序对应 Wallpapers 文件夹里的图片。
/// c1 / c2 是图片左上 / 右下的主色，图片读不到时用它们画渐变占位。
struct BuiltInSpec {
    let name: String
    let category: String
    let c1: UInt32
    let c2: UInt32
}

struct WallpaperItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var subtitle: String
    var kind: Kind
    var fileURL: URL?
    var thumbURL: URL?          // 精选壁纸的小尺寸预览图（界面里用它，设为桌面时用 fileURL 的 4K 原图）
    var palette: [Color]
    var symbol: String
    var category: String        // 精选壁纸的风格分类（用户上传的为空）

    enum Kind: String { case builtIn, image, video }

    /// 界面上显示的名字（英文模式下精选壁纸显示英文名）
    var displayTitle: String {
        guard AppLanguage.isEnglish, kind == .builtIn else { return title }
        return WallpaperLibrary.englishNames[title] ?? title
    }

    init(id: UUID = UUID(), title: String, subtitle: String, kind: Kind, fileURL: URL? = nil, thumbURL: URL? = nil, palette: [Color] = [.blue, .purple], symbol: String = "sparkles", category: String = "") {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.fileURL = fileURL
        self.thumbURL = thumbURL
        self.palette = palette
        self.symbol = symbol
        self.category = category
    }

    static func == (lhs: WallpaperItem, rhs: WallpaperItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

final class WallpaperLibrary: ObservableObject {
    @Published var items: [WallpaperItem] = WallpaperLibrary.makeBuiltIns()
    @Published var selectedID: UUID?
    @Published var activeID: UUID?
    @Published var statusMessage = "准备好为桌面换个新样子"

    // 画面校准（全局设置，会保存）
    @Published var scaleMode: WallpaperScaleMode =
        WallpaperScaleMode(rawValue: UserDefaults.standard.string(forKey: "Lumi.scaleMode") ?? "") ?? .fill {
        didSet { UserDefaults.standard.set(scaleMode.rawValue, forKey: "Lumi.scaleMode") }
    }
    @Published var zoom: Double = UserDefaults.standard.object(forKey: "Lumi.zoom") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(zoom, forKey: "Lumi.zoom") }
    }
    @Published var offsetX: Double = UserDefaults.standard.object(forKey: "Lumi.offsetX") as? Double ?? 0 {
        didSet { UserDefaults.standard.set(offsetX, forKey: "Lumi.offsetX") }
    }
    @Published var offsetY: Double = UserDefaults.standard.object(forKey: "Lumi.offsetY") as? Double ?? 0 {
        didSet { UserDefaults.standard.set(offsetY, forKey: "Lumi.offsetY") }
    }

    var calibration: WallpaperCalibration {
        WallpaperCalibration(mode: scaleMode, zoom: zoom, offsetX: offsetX, offsetY: offsetY)
    }

    func resetCalibration() {
        scaleMode = .fill
        zoom = 1
        offsetX = 0
        offsetY = 0
        calibrationChanged()
    }

    /// 校准参数改变后调用：如果当前选中的就是正在使用的壁纸，立即重新应用。
    func calibrationChanged() {
        guard let id = activeID, id == selectedItem?.id,
              let item = items.first(where: { $0.id == id }) else {
            statusMessage = tr("校准已调整，点击“设为桌面壁纸”后生效", "Calibration changed. Click “Set as Wallpaper” to apply.")
            return
        }
        apply(item)
    }

    private let folderURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("LumiWallpaper/Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    private let metadataURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("LumiWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("library.json")
    }()
    private let renderedFolderURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("LumiWallpaper/Rendered", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    private let backupKey = "LumiWallpaper.previousDesktopURL"

    /// 需要在所有桌面（Space）上保持的壁纸；切换到新桌面时会自动补上。
    private var syncURL: URL?
    /// 同步时是否套用画面校准（恢复原桌面时不套用）
    private var syncCalibrated = true
    private var spaceObserver: NSObjectProtocol?
    private var activityToken: NSObjectProtocol?
    private var anchorWindow: NSWindow?
    private let videoWallpaper = VideoWallpaperController()

    init() {
        statusMessage = tr("准备好为桌面换个新样子", "Ready to give your desktop a new look")
        loadImportedItems()
        selectedID = items.first?.id
        // setDesktopImageURL 只影响"当前"桌面，所以每次切换桌面时重新应用一次
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.syncCurrentSpace() }

        // App 窗口在别的桌面上不可见时，系统可能让它进入 App Nap，导致收不到切换通知
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Keep wallpaper in sync across Spaces")
    }

    deinit {
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
    }

    /// setDesktopImageURL 实际生效的是"本 App 窗口所在的桌面"。
    /// 所以放一个 1x1 的透明窗口并让它出现在所有桌面上，这样无论切到哪个桌面，App 都"在"那里。
    private func ensureAnchorWindow() {
        guard anchorWindow == nil else { return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.orderFrontRegardless()
        anchorWindow = w
    }

    /// 给所有显示器的"当前桌面"设置壁纸。
    /// 注意不能用 desktopImageURL(for:) 判断是否已设置：它返回的是整块屏幕的值，不是每个桌面各自的值。
    /// calibrated 为 false 时用系统默认的"填充"方式（用于恢复原桌面）。
    private func setDesktop(_ source: URL, calibrated: Bool = true) throws {
        let cal = calibrated ? calibration : WallpaperCalibration()
        for screen in NSScreen.screens {
            var url = source
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
            if cal.hasManualAdjust, let rendered = renderedWallpaper(source: source, screen: screen, calibration: cal) {
                // 手动缩放/位移：自己渲染成和屏幕像素完全一致的图片
                url = rendered
                options[.imageScaling] = NSImageScaling.scaleAxesIndependently.rawValue
            } else {
                switch cal.mode {
                case .fill:
                    options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
                    options[.allowClipping] = true
                case .fit:
                    options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
                    options[.allowClipping] = false
                    options[.fillColor] = NSColor.black
                case .stretch:
                    options[.imageScaling] = NSImageScaling.scaleAxesIndependently.rawValue
                }
            }
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    /// 按校准参数把原图渲染成屏幕分辨率的 PNG（同样参数会复用缓存文件）。
    private func renderedWallpaper(source: URL, screen: NSScreen, calibration cal: WallpaperCalibration) -> URL? {
        let scale = screen.backingScaleFactor
        let tw = Int((screen.frame.width * scale).rounded())
        let th = Int((screen.frame.height * scale).rounded())
        let name = "\(source.deletingPathExtension().lastPathComponent)_\(tw)x\(th)_\(cal.mode.rawValue)_z\(Int((cal.zoom * 100).rounded()))_x\(Int((cal.offsetX * 1000).rounded()))_y\(Int((cal.offsetY * 1000).rounded())).png"
        let out = renderedFolderURL.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: out.path) { return out }

        guard tw > 0, th > 0,
              let image = NSImage(contentsOf: source), image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        let target = CGSize(width: tw, height: th)
        let iw = image.size.width, ih = image.size.height
        let base: (CGFloat, CGFloat)
        switch cal.mode {
        case .fill:    let k = max(target.width / iw, target.height / ih); base = (k, k)
        case .fit:     let k = min(target.width / iw, target.height / ih); base = (k, k)
        case .stretch: base = (target.width / iw, target.height / ih)
        }
        let dw = iw * base.0 * cal.zoom, dh = ih * base.1 * cal.zoom
        let rect = CGRect(x: (target.width - dw) / 2 + cal.offsetX * target.width,
                          y: (target.height - dh) / 2 + cal.offsetY * target.height,
                          width: dw, height: dh)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        NSColor.black.setFill()
        NSRect(origin: .zero, size: target).fill()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)   // NSImage 会处理照片方向
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        do { try png.write(to: out, options: .atomic) } catch { return nil }
        pruneRenderedCache()
        return out
    }

    /// 缓存文件超过 40 个时删除最旧的。
    private func pruneRenderedCache() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: renderedFolderURL,
                                                      includingPropertiesForKeys: [.creationDateKey]),
              files.count > 40 else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        for f in sorted.prefix(files.count - 40) { try? fm.removeItem(at: f) }
    }

    private func syncCurrentSpace() {
        guard let url = syncURL else { return }
        // 切换动画结束前设置可能落到旧桌面上，所以立即设置一次，稍后再补一次
        try? setDesktop(url, calibrated: syncCalibrated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, let url = self.syncURL else { return }
            try? self.setDesktop(url, calibrated: self.syncCalibrated)
            self.statusMessage = tr("已同步到当前桌面", "Synced to the current desktop")
        }
    }

    func importFiles(_ urls: [URL]) {
        var added = 0
        for sourceURL in urls {
            let access = sourceURL.startAccessingSecurityScopedResource()
            defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
            let ext = sourceURL.pathExtension.isEmpty ? "file" : sourceURL.pathExtension
            let isVideo = UTType(filenameExtension: ext)?.conforms(to: .movie) == true || UTType(filenameExtension: ext)?.conforms(to: .video) == true
            let isImage = UTType(filenameExtension: ext)?.conforms(to: .image) == true
            guard isVideo || isImage else { continue }
            let destination = folderURL.appendingPathComponent(UUID().uuidString + "." + ext)
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                let item = WallpaperItem(title: sourceURL.deletingPathExtension().lastPathComponent,
                                         subtitle: isVideo ? "个人视频" : "个人照片",
                                         kind: isVideo ? .video : .image,
                                         fileURL: destination,
                                         palette: isVideo ? [.indigo, .black] : [.teal, .blue],
                                         symbol: isVideo ? "play.rectangle.fill" : "photo.fill")
                items.insert(item, at: 0)
                added += 1
            } catch {
                statusMessage = tr("导入失败：", "Import failed: ") + error.localizedDescription
            }
        }
        saveImportedItems()
        if let first = items.first { selectedID = first.id }
        if added > 0 { statusMessage = tr("已导入并保存 \(added) 个文件", "Imported and saved \(added) file(s)") }
    }

    func applySelected() {
        guard let item = selectedItem else { return }
        apply(item)
    }

    private func apply(_ item: WallpaperItem) {
        if item.kind == .video {
            guard let url = item.fileURL else { statusMessage = tr("无法读取这个视频", "Couldn't read this video"); return }
            if videoWallpaper.currentURL == url {
                videoWallpaper.update(calibration)          // 同一个视频：只更新画面，不重新播放
            } else {
                videoWallpaper.start(url: url, calibration: calibration)
            }
            activeID = item.id
            statusMessage = tr("视频壁纸已应用到所有桌面（退出 App 后会停止播放）", "Video wallpaper applied to all desktops (stops when the app quits)")
            return
        }
        videoWallpaper.stop()
        ensureAnchorWindow()
        guard let imageURL = item.fileURL ?? Self.makeWallpaperImage(for: item) else {
            statusMessage = tr("无法读取这张壁纸", "Couldn't read this wallpaper")
            return
        }
        do {
            if UserDefaults.standard.string(forKey: backupKey) == nil,
               let screen = NSScreen.main ?? NSScreen.screens.first,
               let current = NSWorkspace.shared.desktopImageURL(for: screen) {
                UserDefaults.standard.set(current.path, forKey: backupKey)
            }
            try setDesktop(imageURL)
            syncURL = imageURL
            syncCalibrated = true
            activeID = item.id
            statusMessage = tr("已应用到桌面（切换到其他桌面时会自动同步）", "Applied to your desktop (syncs automatically when you switch Spaces)")
        } catch {
            statusMessage = tr("应用失败：", "Couldn't apply: ") + error.localizedDescription
        }
    }

    func restoreDesktop() {
        guard let path = UserDefaults.standard.string(forKey: backupKey) else {
            statusMessage = tr("没有找到本次应用前记录的桌面壁纸", "No previous desktop wallpaper was recorded")
            return
        }
        let url = URL(fileURLWithPath: path)
        videoWallpaper.stop()
        ensureAnchorWindow()
        do {
            try setDesktop(url, calibrated: false)
            syncURL = url   // 其他桌面切过去时也会恢复成原壁纸
            syncCalibrated = false
            UserDefaults.standard.removeObject(forKey: backupKey)
            activeID = nil
            statusMessage = tr("已恢复为之前的桌面壁纸", "Restored your previous desktop wallpaper")
        } catch {
            statusMessage = tr("恢复失败：", "Couldn't restore: ") + error.localizedDescription
        }
    }

    /// 删除用户上传的图片/视频：删除本地文件、渲染缓存和图库记录。
    func delete(_ item: WallpaperItem) {
        guard item.kind != .builtIn else { return }
        var note = tr("已删除“\(item.displayTitle)”", "Deleted “\(item.displayTitle)”")

        // 正在使用的壁纸：先停止/恢复，避免桌面指向已被删除的文件
        if activeID == item.id {
            if item.kind == .video {
                videoWallpaper.stop()
                activeID = nil
            } else if UserDefaults.standard.string(forKey: backupKey) != nil {
                restoreDesktop()
            } else {
                syncURL = nil
                activeID = nil
                note += tr("（它正在作为桌面壁纸，系统桌面可能会变回默认壁纸）", " (it was your current wallpaper, so your desktop may revert to the default)")
            }
        }

        let fm = FileManager.default
        if let url = item.fileURL {
            try? fm.removeItem(at: url)
            let prefix = url.deletingPathExtension().lastPathComponent + "_"
            if let cached = try? fm.contentsOfDirectory(at: renderedFolderURL, includingPropertiesForKeys: nil) {
                cached.filter { $0.lastPathComponent.hasPrefix(prefix) }.forEach { try? fm.removeItem(at: $0) }
            }
        }

        items.removeAll { $0.id == item.id }
        if selectedID == item.id { selectedID = items.first?.id }
        saveImportedItems()
        statusMessage = note
    }

    var selectedItem: WallpaperItem? {
        items.first(where: { $0.id == selectedID }) ?? items.first
    }

    private func saveImportedItems() {
        let imported = items.filter { $0.kind == .image || $0.kind == .video }
        let data = imported.compactMap { item -> [String: String]? in
            guard let url = item.fileURL else { return nil }
            return ["id": item.id.uuidString, "title": item.title, "subtitle": item.subtitle,
                    "kind": item.kind.rawValue, "path": url.path, "symbol": item.symbol]
        }
        if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]) {
            try? encoded.write(to: metadataURL, options: .atomic)
        }
    }

    private func loadImportedItems() {
        guard let data = try? Data(contentsOf: metadataURL),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }
        let restored: [WallpaperItem] = rows.compactMap { row in
            guard let idString = row["id"], let id = UUID(uuidString: idString),
                  let title = row["title"], let kindString = row["kind"], let kind = WallpaperItem.Kind(rawValue: kindString),
                  let path = row["path"] else { return nil }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return WallpaperItem(id: id, title: title, subtitle: row["subtitle"] ?? "我的壁纸", kind: kind,
                                 fileURL: url, palette: kind == .video ? [.indigo, .black] : [.teal, .blue],
                                 symbol: row["symbol"] ?? "photo.fill")
        }
        items.insert(contentsOf: restored, at: 0)
    }

    static func makeWallpaperImage(for item: WallpaperItem) -> URL? {
        let size = NSSize(width: 2560, height: 1600)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        guard let gradient = NSGradient(colors: item.palette.map { NSColor($0) }) ?? NSGradient(starting: .systemBlue, ending: .systemPurple) else {
            image.unlockFocus()
            return nil
        }
        gradient.draw(in: rect, angle: -35)
        let text = item.displayTitle as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 94, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.9)]
        text.draw(at: NSPoint(x: 130, y: 130), withAttributes: attributes)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Lumi-\(item.id.uuidString).png")
        do { try png.write(to: url, options: .atomic); return url } catch { return nil }
    }

    static func makeBuiltIns() -> [WallpaperItem] {
        let palettes: [[Color]] = [
            [.cyan, .blue], [.indigo, .black], [.orange, .pink], [.teal, .blue], [.purple, .indigo],
            [.pink, .purple], [.mint, .teal], [.blue, .purple], [.orange, .red], [.black, .indigo],
            [.cyan, .mint], [.purple, .pink], [.brown, .orange], [.gray, .blue], [.green, .teal],
            [.red, .purple], [.blue, .black], [.yellow, .orange], [.mint, .blue], [.indigo, .pink]
        ]
        let names = ["极光来信", "深海回响", "落日余温", "海岸漫游", "午夜蓝调", "樱花梦境", "薄荷星球", "银河漫步", "橘色日落", "暗夜流光", "青空物语", "粉色云层", "暖棕胶片", "冰川之境", "森林呼吸", "暮色星河", "深空旅行", "柠檬汽水", "清风岛屿", "星云花园"]
        let base: [WallpaperItem] = palettes.enumerated().map { index, palette in
            let bundled = bundledWallpaper(index + 1)
            return WallpaperItem(title: names[index],
                                 subtitle: (bundled != nil ? "精选壁纸 · " : "精选动态风格 · ") + String(format: "%02d", index + 1),
                                 kind: .builtIn, fileURL: bundled?.full, thumbURL: bundled?.thumb,
                                 palette: palette, symbol: ["sparkles", "moon.stars.fill", "sunset.fill", "water.waves", "moon.fill"][index % 5],
                                 category: "精选")
        }
        let extra: [WallpaperItem] = extraCatalog.enumerated().map { offset, spec in
            let number = palettes.count + offset + 1          // 21, 22, ...
            let bundled = bundledWallpaper(number)
            let symbols = categorySymbols[spec.category] ?? ["sparkles"]
            return WallpaperItem(title: spec.name,
                                 subtitle: spec.category + " · " + String(format: "%02d", number),
                                 kind: .builtIn, fileURL: bundled?.full, thumbURL: bundled?.thumb,
                                 palette: [Color(hex: spec.c1), Color(hex: spec.c2)],
                                 symbol: symbols[offset % symbols.count],
                                 category: spec.category)
        }
        return base + extra
    }

    /// 精选壁纸的英文名（key 是中文名）
    static let englishNames: [String: String] = [
        "蜜桃云朵": "Peach Clouds",
        "薰衣草田": "Lavender Fields",
        "玫瑰金": "Rose Gold",
        "糖果气泡": "Candy Bubbles",
        "粉紫黄昏": "Pink-Purple Dusk",
        "奶油晨曦": "Creamy Dawn",
        "梦幻云端": "Dreamy Skies",
        "樱雾粉海": "Sakura Mist Sea",
        "薄荷冰淇淋": "Mint Ice Cream",
        "星月少女": "Star & Moon Girl",
        "樱花飘落": "Falling Sakura",
        "珍珠光泽": "Pearl Sheen",
        "草莓牛奶": "Strawberry Milk",
        "玫瑰雾": "Rose Haze",
        "星屑少女": "Stardust Girl",
        "马卡龙": "Macaron",
        "糖云日落": "Candy Cloud Sunset",
        "棉花糖云": "Cotton Candy Clouds",
        "粉色丝绸": "Pink Silk",
        "爱心泡泡": "Heart Bubbles",
        "深海潜航": "Deep Sea Dive",
        "石墨黑": "Graphite Black",
        "钢铁蓝峰": "Steel Blue Peak",
        "暗夜森林": "Dark Forest",
        "赛博霓虹": "Cyber Neon",
        "熔岩余烬": "Lava Embers",
        "午夜都市蓝": "Midnight City Blue",
        "极光青": "Aurora Cyan",
        "荒漠焦橙": "Desert Burnt Orange",
        "深空蓝紫": "Deep Space Violet",
        "极光来信": "Aurora Letter",
        "翠绿极夜": "Emerald Polar Night",
        "紫幕极光": "Purple Curtain Aurora",
        "冰蓝极光": "Ice Blue Aurora",
        "深海回响": "Deep Sea Echo",
        "月下银波": "Silver Moon Waves",
        "紫夜海": "Violet Night Sea",
        "海岸漫游": "Coastal Drift",
        "晴空碧海": "Clear Sky, Blue Sea",
        "暖阳海湾": "Sunny Bay",
        "落日余晖": "Sunset Glow",
        "晚霞山脊": "Sunset Ridge",
        "玫瑰黄昏": "Rose Dusk",
        "靛蓝黎明": "Indigo Dawn",
        "金色时刻": "Golden Hour",
        "薄雾晨光": "Misty Morning",
        "紫金山河": "Purple-Gold Mountains",
        "冰川之境": "Glacier Realm",
        "森林呼吸": "Forest Breath",
        "云海山峦": "Sea of Clouds",
        "雪岭晨曦": "Snowy Ridge Dawn",
        "橘色日落": "Orange Sunset",
        "沙丘暖阳": "Warm Dunes",
        "玫瑰沙漠": "Rose Desert",
        "午夜蓝调": "Midnight Blues",
        "暮色星河": "Dusk Starfield",
        "银河倾泻": "Pouring Galaxy",
        "紫夜流云": "Violet Night Clouds",
        "青空物语": "Blue Sky Tale",
        "粉色云层": "Pink Clouds",
        "夏日晴空": "Summer Sky",
        "黄昏云海": "Dusk Cloud Sea",
        "樱花梦境": "Sakura Dream",
        "薄荷星球": "Mint Planet",
        "暖棕胶片": "Warm Film",
        "蜜桃汽水": "Peach Soda",
        "海盐蓝调": "Sea Salt Blue",
        "晨雾灰粉": "Morning Mist Blush",
        "银河漫步": "Galaxy Walk",
        "深空旅行": "Deep Space Voyage",
        "星云涡旋": "Nebula Swirl",
        "极夜幻彩": "Polar Night Glow",
        "暗夜流光": "Night Glow",
        "霓虹脉络": "Neon Veins",
        "青橙电波": "Teal-Orange Wave",
        "柠檬汽水": "Lemon Soda",
        "薄暮光斑": "Twilight Bokeh",
        "蓝莓气泡": "Blueberry Fizz",
        "远岛晴空": "Distant Isle",
        "暮色孤岛": "Lone Isle at Dusk",
        "落日余温": "Sunset Afterglow",
        "清风岛屿": "Breezy Isle",
        "星云花园": "Nebula Garden"
    ]

    /// 界面里分类标签的顺序和图标
    static let categoryOrder = ["少女系", "深色科技", "风景渐变", "精选"]
    static let categoryIcons: [String: String] = [
        "少女系": "heart.fill", "深色科技": "bolt.fill", "风景渐变": "mountain.2.fill", "精选": "sparkles"
    ]
    static let categorySymbols: [String: [String]] = [
        "少女系": ["heart.fill", "sparkles", "cloud.fill", "star.fill", "moon.stars.fill"],
        "深色科技": ["bolt.fill", "moon.fill", "flame.fill", "sparkle", "water.waves"],
        "风景渐变": ["sunset.fill", "mountain.2.fill", "water.waves", "leaf.fill", "cloud.sun.fill"]
    ]

    static let extraCatalog: [BuiltInSpec] = [
        BuiltInSpec(name: "蜜桃云朵", category: "少女系", c1: 0xF6B9C9, c2: 0xF4D2CC),
        BuiltInSpec(name: "薰衣草田", category: "少女系", c1: 0xD5B1E9, c2: 0xDAC8F5),
        BuiltInSpec(name: "玫瑰金", category: "少女系", c1: 0xF0CBBD, c2: 0xE2B8B4),
        BuiltInSpec(name: "糖果气泡", category: "少女系", c1: 0xEFC1DF, c2: 0xDAB9F0),
        BuiltInSpec(name: "粉紫黄昏", category: "少女系", c1: 0xA778C7, c2: 0x895F8D),
        BuiltInSpec(name: "奶油晨曦", category: "少女系", c1: 0xF5E0E2, c2: 0xF5D2C1),
        BuiltInSpec(name: "梦幻云端", category: "少女系", c1: 0xC5A3E3, c2: 0xEDCADD),
        BuiltInSpec(name: "樱雾粉海", category: "少女系", c1: 0xF0B8CA, c2: 0xC78AB7),
        BuiltInSpec(name: "薄荷冰淇淋", category: "少女系", c1: 0xE0DDE4, c2: 0xC1E7D8),
        BuiltInSpec(name: "星月少女", category: "少女系", c1: 0xBE7FD4, c2: 0x986FA5),
        BuiltInSpec(name: "樱花飘落", category: "少女系", c1: 0xFDDBE9, c2: 0xFAC3D8),
        BuiltInSpec(name: "珍珠光泽", category: "少女系", c1: 0xF9EAF5, c2: 0xEFDBFA),
        BuiltInSpec(name: "草莓牛奶", category: "少女系", c1: 0xFDD2DE, c2: 0xFCD9E4),
        BuiltInSpec(name: "玫瑰雾", category: "少女系", c1: 0xE9B7C2, c2: 0xEDC2CB),
        BuiltInSpec(name: "星屑少女", category: "少女系", c1: 0xD6B8FC, c2: 0xF5C1E8),
        BuiltInSpec(name: "马卡龙", category: "少女系", c1: 0xF6DBCF, c2: 0xF7D4DF),
        BuiltInSpec(name: "糖云日落", category: "少女系", c1: 0xD2A8E5, c2: 0xC387BA),
        BuiltInSpec(name: "棉花糖云", category: "少女系", c1: 0xE9D8F9, c2: 0xF7DDE6),
        BuiltInSpec(name: "粉色丝绸", category: "少女系", c1: 0xFAC9DB, c2: 0xFAC8DB),
        BuiltInSpec(name: "爱心泡泡", category: "少女系", c1: 0xFCC8DE, c2: 0xFBBFDA),
        BuiltInSpec(name: "深海潜航", category: "深色科技", c1: 0x081321, c2: 0x0D1E30),
        BuiltInSpec(name: "石墨黑", category: "深色科技", c1: 0x262A33, c2: 0x20232B),
        BuiltInSpec(name: "钢铁蓝峰", category: "深色科技", c1: 0x122745, c2: 0x1B2A42),
        BuiltInSpec(name: "暗夜森林", category: "深色科技", c1: 0x132420, c2: 0x102219),
        BuiltInSpec(name: "赛博霓虹", category: "深色科技", c1: 0x263149, c2: 0x151E31),
        BuiltInSpec(name: "熔岩余烬", category: "深色科技", c1: 0x9A3E15, c2: 0x4C1708),
        BuiltInSpec(name: "午夜都市蓝", category: "深色科技", c1: 0x13295D, c2: 0x0E1F45),
        BuiltInSpec(name: "极光青", category: "深色科技", c1: 0x155C71, c2: 0x05141C),
        BuiltInSpec(name: "荒漠焦橙", category: "深色科技", c1: 0x5C3018, c2: 0x5A2C1B),
        BuiltInSpec(name: "深空蓝紫", category: "深色科技", c1: 0x3264C2, c2: 0x1B3885),
        BuiltInSpec(name: "极光来信", category: "风景渐变", c1: 0x246A7E, c2: 0x081C28),
        BuiltInSpec(name: "翠绿极夜", category: "风景渐变", c1: 0x2C6F4B, c2: 0x071B16),
        BuiltInSpec(name: "紫幕极光", category: "风景渐变", c1: 0x5D388D, c2: 0x110A2C),
        BuiltInSpec(name: "冰蓝极光", category: "风景渐变", c1: 0x315585, c2: 0x09192D),
        BuiltInSpec(name: "深海回响", category: "风景渐变", c1: 0x141F30, c2: 0x152539),
        BuiltInSpec(name: "月下银波", category: "风景渐变", c1: 0x344562, c2: 0x1E344F),
        BuiltInSpec(name: "紫夜海", category: "风景渐变", c1: 0x301C4A, c2: 0x372351),
        BuiltInSpec(name: "海岸漫游", category: "风景渐变", c1: 0x83BCEA, c2: 0x4E9AB3),
        BuiltInSpec(name: "晴空碧海", category: "风景渐变", c1: 0x8ECAF5, c2: 0x297BA0),
        BuiltInSpec(name: "暖阳海湾", category: "风景渐变", c1: 0xF7B99A, c2: 0x398E97),
        BuiltInSpec(name: "落日余晖", category: "风景渐变", c1: 0x703F72, c2: 0x4F2B51),
        BuiltInSpec(name: "晚霞山脊", category: "风景渐变", c1: 0x80587C, c2: 0x58305D),
        BuiltInSpec(name: "玫瑰黄昏", category: "风景渐变", c1: 0x8A5388, c2: 0x714471),
        BuiltInSpec(name: "靛蓝黎明", category: "风景渐变", c1: 0x27306E, c2: 0x45458B),
        BuiltInSpec(name: "金色时刻", category: "风景渐变", c1: 0xE3834F, c2: 0x683836),
        BuiltInSpec(name: "薄雾晨光", category: "风景渐变", c1: 0xA5A5CE, c2: 0x665684),
        BuiltInSpec(name: "紫金山河", category: "风景渐变", c1: 0x52285F, c2: 0x582E62),
        BuiltInSpec(name: "冰川之境", category: "风景渐变", c1: 0x4C6AA0, c2: 0x465980),
        BuiltInSpec(name: "森林呼吸", category: "风景渐变", c1: 0xE2EBE7, c2: 0x4A6D5E),
        BuiltInSpec(name: "云海山峦", category: "风景渐变", c1: 0x7E95C8, c2: 0x595180),
        BuiltInSpec(name: "雪岭晨曦", category: "风景渐变", c1: 0xA8B8D6, c2: 0x5A6189),
        BuiltInSpec(name: "橘色日落", category: "风景渐变", c1: 0xEAA678, c2: 0x804E3C),
        BuiltInSpec(name: "沙丘暖阳", category: "风景渐变", c1: 0xFBC085, c2: 0x83503A),
        BuiltInSpec(name: "玫瑰沙漠", category: "风景渐变", c1: 0xCD7997, c2: 0x865269),
        BuiltInSpec(name: "午夜蓝调", category: "风景渐变", c1: 0x3F4B93, c2: 0x35406D),
        BuiltInSpec(name: "暮色星河", category: "风景渐变", c1: 0x814294, c2: 0x6E357E),
        BuiltInSpec(name: "银河倾泻", category: "风景渐变", c1: 0x273560, c2: 0x162140),
        BuiltInSpec(name: "紫夜流云", category: "风景渐变", c1: 0x5F4396, c2: 0x593F88),
        BuiltInSpec(name: "青空物语", category: "风景渐变", c1: 0x4982DF, c2: 0x85B4F0),
        BuiltInSpec(name: "粉色云层", category: "风景渐变", c1: 0xAE88C6, c2: 0xE2B6C8),
        BuiltInSpec(name: "夏日晴空", category: "风景渐变", c1: 0x3794E4, c2: 0xA4CFEE),
        BuiltInSpec(name: "黄昏云海", category: "风景渐变", c1: 0x9A70A1, c2: 0xF0AB8B),
        BuiltInSpec(name: "樱花梦境", category: "风景渐变", c1: 0xF3D8E8, c2: 0xE9C2E3),
        BuiltInSpec(name: "薄荷星球", category: "风景渐变", c1: 0x95DCCA, c2: 0xB6E8DD),
        BuiltInSpec(name: "暖棕胶片", category: "风景渐变", c1: 0xB56535, c2: 0xB67850),
        BuiltInSpec(name: "蜜桃汽水", category: "风景渐变", c1: 0xF6A383, c2: 0xF6BAA6),
        BuiltInSpec(name: "海盐蓝调", category: "风景渐变", c1: 0x709DD7, c2: 0xA2D0EF),
        BuiltInSpec(name: "晨雾灰粉", category: "风景渐变", c1: 0xCBB8CB, c2: 0xDFC9D4),
        BuiltInSpec(name: "银河漫步", category: "风景渐变", c1: 0x37298F, c2: 0x7382DF),
        BuiltInSpec(name: "深空旅行", category: "风景渐变", c1: 0x3B228A, c2: 0x261B63),
        BuiltInSpec(name: "星云涡旋", category: "风景渐变", c1: 0xDDA296, c2: 0x491B5C),
        BuiltInSpec(name: "极夜幻彩", category: "风景渐变", c1: 0x8E8AE0, c2: 0x15525D),
        BuiltInSpec(name: "暗夜流光", category: "风景渐变", c1: 0x1A1528, c2: 0x2B203A),
        BuiltInSpec(name: "霓虹脉络", category: "风景渐变", c1: 0x14182C, c2: 0x172135),
        BuiltInSpec(name: "青橙电波", category: "风景渐变", c1: 0x418B8E, c2: 0x5F7477),
        BuiltInSpec(name: "柠檬汽水", category: "风景渐变", c1: 0xD6E774, c2: 0xB0DB64),
        BuiltInSpec(name: "薄暮光斑", category: "风景渐变", c1: 0x6C3F7F, c2: 0xC8728D),
        BuiltInSpec(name: "蓝莓气泡", category: "风景渐变", c1: 0x3A498F, c2: 0x6079CD),
        BuiltInSpec(name: "远岛晴空", category: "风景渐变", c1: 0x9ED4F9, c2: 0x4C99B0),
        BuiltInSpec(name: "暮色孤岛", category: "风景渐变", c1: 0x965C8D, c2: 0x593B6C)
    ]

    /// 在 App 包里找精选壁纸（原图 wall_01.png + 缩略图 wall_01_thumb.jpg）。找不到就返回 nil，界面会退回到渐变色。
    static func bundledWallpaper(_ index: Int) -> (full: URL, thumb: URL)? {
        let name = String(format: "wall_%02d", index)
        func find(_ resource: String, _ extensions: [String]) -> URL? {
            for ext in extensions {
                if let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: "Wallpapers")
                    ?? Bundle.main.url(forResource: resource, withExtension: ext) { return url }
            }
            return nil
        }
        guard let full = find(name, ["png", "jpg"]), let thumb = find(name + "_thumb", ["jpg", "png"]) else { return nil }
        return (full, thumb)
    }
}

/// 把视频放在桌面图标下面、系统壁纸上面，循环静音播放。
/// 窗口设置为"出现在所有桌面"，所以所有桌面都会同时显示，不需要切换同步。
final class VideoWallpaperController {
    private var windows: [NSWindow] = []
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var screenObserver: NSObjectProtocol?
    private var layers: [AVPlayerLayer] = []
    private var calibration = WallpaperCalibration()
    private(set) var currentURL: URL?

    func start(url: URL, calibration: WallpaperCalibration) {
        stop()
        self.calibration = calibration
        currentURL = url
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        player = queue
        buildWindows()
        queue.play()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.buildWindows() }
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        player?.pause()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        layers.removeAll()
        looper = nil
        player = nil
        currentURL = nil
    }

    /// 校准参数变化时实时更新画面，不需要重新播放。
    func update(_ calibration: WallpaperCalibration) {
        self.calibration = calibration
        layers.forEach { style($0) }
    }

    private func style(_ layer: AVPlayerLayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch calibration.mode {
        case .fill:    layer.videoGravity = .resizeAspectFill
        case .fit:     layer.videoGravity = .resizeAspect
        case .stretch: layer.videoGravity = .resize
        }
        let size = layer.bounds.size
        var t = CATransform3DMakeTranslation(calibration.offsetX * size.width, calibration.offsetY * size.height, 0)
        t = CATransform3DScale(t, calibration.zoom, calibration.zoom, 1)   // 先缩放再平移
        layer.transform = t
        CATransaction.commit()
    }

    private func buildWindows() {
        guard let player else { return }
        windows.forEach { $0.orderOut(nil) }
        layers.removeAll()
        windows = NSScreen.screens.map { makeWindow(for: $0, player: player) }
    }

    private func makeWindow(for screen: NSScreen, player: AVPlayer) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: screen.frame.size),
                         styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        w.isReleasedWhenClosed = false
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.ignoresMouseEvents = true
        w.isOpaque = true
        w.backgroundColor = .black
        w.hasShadow = false

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        view.layer?.masksToBounds = true
        view.layer?.addSublayer(layer)
        style(layer)
        layers.append(layer)
        w.contentView = view

        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        return w
    }
}
