import AppKit

enum AppIconChoice: String, CaseIterable, Identifiable {
    case lightBranchLens = "01"
    case lightRepositoryFold = "02"
    case lightCommitPulse = "03"
    case lightFilterStack = "04"
    case lightMergeRibbon = "05"
    case lightStageTray = "06"
    case lightGraphCompass = "07"
    case lightWorktreePanels = "08"
    case lightRuleCards = "09"
    case lightOrbitMerge = "10"
    case darkNeonFork = "11"
    case darkNegativeG = "12"
    case darkConstellation = "13"
    case darkTerminalBloom = "14"
    case darkMergePortal = "15"
    case darkStashCapsule = "16"
    case darkFocusShield = "17"
    case darkWorktreeGrid = "18"
    case darkSignalMerge = "19"
    case darkRuleFile = "20"

    var id: String { rawValue }
    var assetName: String { "GitIgnoreIcon\(rawValue)" }
    var isLight: Bool { (Int(rawValue, radix: 10) ?? 0) <= 10 }

    static var lightChoices: [Self] { allCases.filter(\.isLight) }
    static var darkChoices: [Self] { allCases.filter { !$0.isLight } }

    var title: String {
        switch self {
        case .lightBranchLens: "枝影镜片"
        case .lightRepositoryFold: "仓库折角"
        case .lightCommitPulse: "提交脉冲"
        case .lightFilterStack: "筛选层叠"
        case .lightMergeRibbon: "合并缎带"
        case .lightStageTray: "Stage 托盘"
        case .lightGraphCompass: "图谱罗盘"
        case .lightWorktreePanels: "工作树窗格"
        case .lightRuleCards: "规则卡片"
        case .lightOrbitMerge: "轨道合并"
        case .darkNeonFork: "霓虹分叉"
        case .darkNegativeG: "暗夜 G"
        case .darkConstellation: "提交星图"
        case .darkTerminalBloom: "终端生长"
        case .darkMergePortal: "合并入口"
        case .darkStashCapsule: "Stash 胶囊"
        case .darkFocusShield: "聚焦护盾"
        case .darkWorktreeGrid: "工作树矩阵"
        case .darkSignalMerge: "信号合流"
        case .darkRuleFile: "夜间规则"
        }
    }
}

@MainActor
enum AppIconController {
    static let storageKey = "gitignore.appIconChoice"
    static let didChangeNotification = Notification.Name("gitignore.appIconDidChange")
    private static var lastAppliedRawValue: String?
    private static var cachedIconData: [String: Data] = [:]

    static func restorePersistedChoice(synchronizeSystemIcon: Bool = false) {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
            ?? AppIconChoice.lightCommitPulse.rawValue
        apply(
            rawValue: rawValue,
            persistToBundle: synchronizeSystemIcon,
            forceRuntimeIcon: true
        )
    }

    static func apply(
        rawValue: String,
        persistToBundle: Bool = false,
        refreshSystemCaches: Bool = false,
        forceRuntimeIcon: Bool = false
    ) {
        let choice = AppIconChoice(rawValue: rawValue) ?? .lightCommitPulse
        let shouldApplyRuntimeIcon = forceRuntimeIcon || refreshSystemCaches || lastAppliedRawValue != choice.rawValue
        guard shouldApplyRuntimeIcon || persistToBundle else { return }
        guard let image = loadImage(for: choice) else { return }
        image.isTemplate = false
        image.size = NSSize(width: 512, height: 512)

        if shouldApplyRuntimeIcon {
            lastAppliedRawValue = choice.rawValue
            NSApplication.shared.applicationIconImage = image
            for window in NSApplication.shared.windows {
                window.miniwindowImage = image
            }
            NSApplication.shared.dockTile.contentView = nil
            NSApplication.shared.dockTile.display()
        }

        if let iconData = cachedIconData[choice.rawValue] ?? makeICNSData(from: image) {
            cachedIconData[choice.rawValue] = iconData
            Task.detached(priority: .utility) {
                persistSupportIcon(iconData, rawValue: choice.rawValue)
                if persistToBundle {
                    persistIcon(iconData, for: Bundle.main.bundlePath, forceRefresh: refreshSystemCaches)
                }
            }
        }

        if shouldApplyRuntimeIcon {
            NotificationCenter.default.post(
                name: didChangeNotification,
                object: nil,
                userInfo: ["rawValue": choice.rawValue]
            )
        }
    }

    private static func loadImage(for choice: AppIconChoice) -> NSImage? {
        let persistedURL = supportIconURL(rawValue: choice.rawValue)
        return NSImage(contentsOf: persistedURL)
            ?? NSImage(named: NSImage.Name(choice.assetName))
            ?? Bundle.main.image(forResource: NSImage.Name(choice.assetName))
    }

    nonisolated private static func supportIconURL(rawValue: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitIgnore/AppIcons", isDirectory: true)
            .appendingPathComponent("\(rawValue).icns")
    }

    nonisolated private static func persistSupportIcon(_ iconData: Data, rawValue: String) {
        let iconURL = supportIconURL(rawValue: rawValue)
        try? FileManager.default.createDirectory(
            at: iconURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? iconData.write(to: iconURL, options: .atomic)
    }

    private static func makeICNSData(from image: NSImage) -> Data? {
        let definitions: [(String, Int)] = [
            ("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
            ("ic08", 256), ("ic09", 512), ("ic10", 1024)
        ]
        var chunks = Data()
        for (type, size) in definitions {
            guard let payload = pngData(from: image, size: size) else { return nil }
            chunks.append(type.data(using: .ascii) ?? Data())
            appendUInt32(UInt32(payload.count + 8), to: &chunks)
            chunks.append(payload)
        }
        var result = Data("icns".utf8)
        appendUInt32(UInt32(chunks.count + 8), to: &result)
        result.append(chunks)
        return result
    }

    private static func pngData(from image: NSImage, size: Int) -> Data? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        representation.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return representation.representation(using: .png, properties: [:])
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    nonisolated private static func persistIcon(_ iconData: Data, for bundlePath: String, forceRefresh: Bool) {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        let iconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let currentIcon = try? Data(contentsOf: iconURL)
        var infoChanged = false
        var updatedInfoData: Data?
        if let infoData = try? Data(contentsOf: infoURL),
           let propertyList = try? PropertyListSerialization.propertyList(from: infoData, options: [], format: nil),
           var info = propertyList as? [String: Any] {
            infoChanged = info["CFBundleIconName"] != nil || (info["CFBundleIconFile"] as? String) != "AppIcon.icns"
            info.removeValue(forKey: "CFBundleIconName")
            info["CFBundleIconFile"] = "AppIcon.icns"
            updatedInfoData = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        }
        if !forceRefresh, currentIcon == iconData, !infoChanged { return }
        do {
            try iconData.write(to: iconURL, options: .atomic)
            if let updatedInfoData { try updatedInfoData.write(to: infoURL, options: .atomic) }
        } catch {
            return
        }

        let legacyIconURL = bundleURL.appendingPathComponent("Icon\r")
        try? FileManager.default.removeItem(at: legacyIconURL)
        run("/usr/bin/xattr", arguments: ["-d", "com.apple.FinderInfo", bundlePath])
        run("/usr/bin/xattr", arguments: ["-d", "com.apple.ResourceFork", bundlePath])
        run("/usr/bin/codesign", arguments: [
            "--force", "--deep", "--sign", "-",
            "--identifier", "com.hengyee.Orbit",
            "--requirements", "=designated => identifier \"com.hengyee.Orbit\"",
            bundlePath
        ])
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: bundlePath)
        run(
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            arguments: ["-f", bundlePath]
        )
        // UserNotifications caches the bundle icon independently from Dock and
        // LaunchServices. Restarting the per-user daemon makes future banners
        // resolve the newly registered icon without altering delivered alerts.
        run("/usr/bin/killall", arguments: ["usernoted"], waits: false)
        run("/usr/bin/killall", arguments: ["Dock"], waits: false)
    }

    nonisolated private static func run(_ executable: String, arguments: [String], waits: Bool = true) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        if waits { process.waitUntilExit() }
    }
}
