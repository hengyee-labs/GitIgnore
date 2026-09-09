import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum SidebarFooterIconPreferences {
    static let symbolKey = "orbit.sidebarFooter.iconSymbol"
    static let customImageKey = "orbit.sidebarFooter.iconImage"
    static let defaultSymbol = "quote.opening"

    static let symbols = [
        "quote.opening", "sparkles", "bolt.fill", "flame.fill", "leaf.fill",
        "heart.fill", "star.fill", "moon.stars.fill", "sun.max.fill", "cloud.fill",
        "drop.fill", "snowflake", "wind", "paperplane.fill", "rocket.fill",
        "lightbulb.fill", "target", "scope", "compass.drawing", "map.fill",
        "flag.fill", "bookmark.fill", "tag.fill", "pin.fill", "bell.fill",
        "clock.fill", "hourglass", "calendar", "checkmark.seal.fill", "shield.fill",
        "lock.fill", "key.fill", "gearshape.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "terminal.fill", "command", "chevron.left.forwardslash.chevron.right", "curlybraces",
        "point.3.connected.trianglepath.dotted", "arrow.triangle.branch", "arrow.triangle.merge",
        "externaldrive.fill", "folder.fill", "doc.text.fill", "tray.fill", "archivebox.fill",
        "shippingbox.fill", "cube.fill", "circle.hexagongrid.fill"
    ]
}

struct SidebarFooterIcon: View {
    @AppStorage(SidebarFooterIconPreferences.symbolKey) private var symbol = SidebarFooterIconPreferences.defaultSymbol
    @AppStorage(SidebarFooterIconPreferences.customImageKey) private var customImageData = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: CGFloat

    var body: some View {
        SidebarFooterIconImage(
            symbol: symbol,
            encodedImage: customImageData,
            symbolSize: size * 0.42,
            animatesChanges: !reduceMotion
        )
        .frame(width: size, height: size)
        .background(OrbitDesign.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.27))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SidebarFooterIconImage: NSViewRepresentable {
    let symbol: String
    let encodedImage: String
    let symbolSize: CGFloat
    let animatesChanges: Bool

    final class Coordinator {
        var symbol = ""
        var encodedImage = ""
        var hasRendered = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.imageScaling = .scaleProportionallyUpOrDown
        updateImageView(imageView, coordinator: context.coordinator)
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        guard context.coordinator.symbol != symbol || context.coordinator.encodedImage != encodedImage else {
            return
        }
        updateImageView(imageView, coordinator: context.coordinator)
    }

    private func updateImageView(_ imageView: NSImageView, coordinator: Coordinator) {
        let customImage = Data(base64Encoded: encodedImage).flatMap(NSImage.init(data:))
        if let customImage {
            imageView.image = customImage
            imageView.contentTintColor = nil
        } else {
            let configuration = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
            let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: SidebarFooterIconPreferences.defaultSymbol, accessibilityDescription: nil)
            imageView.image = symbolImage?.withSymbolConfiguration(configuration)
            imageView.contentTintColor = NSColor(srgbRed: 0.16, green: 0.62, blue: 0.43, alpha: 1)
        }

        coordinator.symbol = symbol
        coordinator.encodedImage = encodedImage
        if coordinator.hasRendered && animatesChanges {
            imageView.alphaValue = 0.72
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                imageView.animator().alphaValue = 1
            }
        } else {
            imageView.alphaValue = 1
            coordinator.hasRendered = true
        }
    }
}

struct SidebarFooterIconSettings: View {
    @AppStorage(SidebarFooterIconPreferences.symbolKey) private var symbol = SidebarFooterIconPreferences.defaultSymbol
    @AppStorage(SidebarFooterIconPreferences.customImageKey) private var customImageData = ""
    @State private var importsImage = false
    @State private var importMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppLanguage.text("签名图标", "Signature Icon")).orbitFont(.caption, weight: .semibold)
                Spacer()
                Button(AppLanguage.text("上传自定义图标…", "Upload Custom Icon…")) { importsImage = true }
                    .controlSize(.small)
                if !customImageData.isEmpty {
                    Button(AppLanguage.text("恢复内置图标", "Restore Built-in Icon")) { customImageData = "" }
                        .controlSize(.small)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 10), spacing: 7) {
                ForEach(Array(SidebarFooterIconPreferences.symbols.enumerated()), id: \.offset) { index, name in
                    let label = AppLanguage.text("签名图标 \(index + 1)", "Signature icon \(index + 1)")
                    let isSelected = symbol == name && customImageData.isEmpty
                    Button {
                        symbol = name
                        customImageData = ""
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : OrbitDesign.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(isSelected ? OrbitDesign.accent : OrbitDesign.surface,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? OrbitDesign.accent : OrbitDesign.separator, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(label)
                    .accessibilityLabel(label)
                    .accessibilityValue(isSelected ? AppLanguage.text("已选择", "Selected") : "")
                }
            }

            if let importMessage {
                Text(importMessage).orbitFont(.caption2).foregroundStyle(OrbitDesign.coral)
            }
        }
        .fileImporter(isPresented: $importsImage, allowedContentTypes: [.image]) { result in
            importImage(result)
        }
    }

    private func importImage(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let sourceData = try Data(contentsOf: url, options: .mappedIfSafe)
            guard sourceData.count <= 5_000_000, let iconData = normalizedIconData(from: sourceData) else {
                importMessage = AppLanguage.text(
                    "图片无法读取或超过 5 MB，请选择 PNG、JPG、HEIC 或 WebP。",
                    "The image cannot be read or exceeds 5 MB. Choose PNG, JPG, HEIC, or WebP."
                )
                return
            }
            customImageData = iconData.base64EncodedString()
            importMessage = nil
        } catch {
            importMessage = AppLanguage.text(
                "没有读取到所选图片，请重试。",
                "The selected image could not be read. Please try again."
            )
        }
    }

    private func normalizedIconData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let side = min(thumbnail.width, thumbnail.height)
        let cropRect = CGRect(
            x: (thumbnail.width - side) / 2,
            y: (thumbnail.height - side) / 2,
            width: side,
            height: side
        )
        guard let croppedImage = thumbnail.cropping(to: cropRect) else { return nil }
        return NSBitmapImageRep(cgImage: croppedImage).representation(using: .png, properties: [:])
    }
}
