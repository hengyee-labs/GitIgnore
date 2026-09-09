import SwiftUI
import AppKit
import CoreText

private extension NSColor {
    static func orbitAdaptive(
        light: UInt32,
        dark: UInt32,
        highContrastLight: UInt32? = nil,
        highContrastDark: UInt32? = nil
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastAqua,
                .darkAqua,
                .aqua
            ])
            let hex: UInt32
            switch match {
            case .accessibilityHighContrastDarkAqua:
                hex = highContrastDark ?? dark
            case .accessibilityHighContrastAqua:
                hex = highContrastLight ?? light
            case .darkAqua:
                hex = dark
            default:
                hex = light
            }
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}

enum OrbitDesign {
    // Stable opaque surfaces are the foundation in both modes. Glass is reserved
    // for window chrome and one emphasized panel, so content never turns foggy.
    static let nsCanvas = NSColor.orbitAdaptive(light: 0xFFFFFF, dark: 0x16191E)
    static let opaqueCanvas = Color(nsColor: nsCanvas)
    static let opaqueSurface = Color(nsColor: .orbitAdaptive(light: 0xFFFFFF, dark: 0x1D2229))
    static let opaqueElevatedSurface = Color(nsColor: .orbitAdaptive(light: 0xFFFFFF, dark: 0x232932))

    static let canvas = opaqueCanvas
    static let sidebar = Color(nsColor: .orbitAdaptive(light: 0xF8F9FA, dark: 0x111419))
    static let chrome = Color(nsColor: .orbitAdaptive(light: 0xFFFFFF, dark: 0x15191E))
    static let surface = opaqueSurface
    static let elevatedSurface = opaqueElevatedSurface
    static let recessedSurface = Color(nsColor: .orbitAdaptive(light: 0xF0F2F5, dark: 0x101318))
    static let selectionFill = Color(nsColor: .orbitAdaptive(light: 0xE8F2ED, dark: 0x1B342D, highContrastLight: 0xD8ECE3, highContrastDark: 0x21483C))
    static let hoverFill = Color(nsColor: .orbitAdaptive(light: 0xF0F2F4, dark: 0x242A32))
    static let separator = Color(nsColor: .orbitAdaptive(light: 0xE5E7EB, dark: 0x343B45, highContrastLight: 0xAEB7C2, highContrastDark: 0x66717F))
    static let panelBorder = Color(nsColor: .orbitAdaptive(light: 0xDDE2E7, dark: 0x3A424E, highContrastLight: 0x8D99A8, highContrastDark: 0x748090))
    static let primaryText = Color(nsColor: .orbitAdaptive(light: 0x111318, dark: 0xEAF0F5, highContrastLight: 0x050608, highContrastDark: 0xFFFFFF))
    static let secondaryText = Color(nsColor: .orbitAdaptive(light: 0x4B5563, dark: 0xA8B2BF, highContrastLight: 0x27313D, highContrastDark: 0xD5DDE6))
    static let tertiaryText = Color(nsColor: .orbitAdaptive(light: 0x707B88, dark: 0x7F8A98, highContrastLight: 0x3E4A58, highContrastDark: 0xBBC5D1))

    static let accent = Color(nsColor: .orbitAdaptive(light: 0x218A67, dark: 0x4AC79A))
    static let accentSoft = Color(nsColor: .orbitAdaptive(light: 0x53A98A, dark: 0x69D6AC))
    static let violet = Color(nsColor: .orbitAdaptive(light: 0x7064C9, dark: 0x9588E8))
    static let coral = Color(nsColor: .orbitAdaptive(light: 0xC85151, dark: 0xFF7B72))
    static let amber = Color(nsColor: .orbitAdaptive(light: 0xA96F18, dark: 0xE0AA4F))
    static let blue = Color(nsColor: .orbitAdaptive(light: 0x326FBD, dark: 0x63A0E8))
    static let cornerRadius: CGFloat = 12

    static var feedbackAnimation: Animation { .easeOut(duration: 0.18) }
    static var completionAnimation: Animation { .easeOut(duration: 0.26) }
}

enum OrbitGlassPreferences {
    static let storageKey = "orbit.glassEffectsEnabled"
}

struct OrbitWindowBackdrop: View {
    @AppStorage(OrbitGlassPreferences.storageKey) private var isEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let usesMaterial = isEnabled && !reduceTransparency
        ZStack {
            OrbitDesign.opaqueCanvas
            OrbitNativeVisualEffect(
                material: .underWindowBackground,
                blendingMode: .withinWindow,
                isEnabled: usesMaterial,
                controlsWindowOpacity: true
            )
                .opacity(usesMaterial ? 1 : 0)
            OrbitDesign.canvas.opacity(usesMaterial ? 0.995 : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.16), value: isEnabled)
    }
}

struct OrbitPanelBackground: View {
    var cornerRadius: CGFloat = 11
    var emphasis = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(emphasis ? OrbitDesign.elevatedSurface : OrbitDesign.surface)
    }
}

enum OrbitChromeRegion {
    case sidebar
    case toolbar

    var solidColor: Color { self == .sidebar ? OrbitDesign.sidebar : OrbitDesign.chrome }
    var material: NSVisualEffectView.Material { self == .sidebar ? .sidebar : .headerView }
    var blendingMode: NSVisualEffectView.BlendingMode { self == .sidebar ? .behindWindow : .withinWindow }

    func tintOpacity(for colorScheme: ColorScheme) -> Double {
        switch self {
        case .sidebar:
            colorScheme == .dark ? 0.62 : 0.52
        case .toolbar:
            colorScheme == .dark ? 0.985 : 0.995
        }
    }
}

struct OrbitChromeBackground: View {
    @AppStorage(OrbitGlassPreferences.storageKey) private var isEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let region: OrbitChromeRegion

    var body: some View {
        let usesMaterial = isEnabled && !reduceTransparency
        ZStack {
            region.solidColor
            if usesMaterial {
                OrbitNativeVisualEffect(
                    material: region.material,
                    blendingMode: region.blendingMode,
                    isEnabled: true,
                    controlsWindowOpacity: false
                )
                region.solidColor.opacity(region.tintOpacity(for: colorScheme))

                if region == .sidebar {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.055 : 0.22),
                            Color.white.opacity(colorScheme == .dark ? 0.018 : 0.06),
                            OrbitDesign.accent.opacity(colorScheme == .dark ? 0.022 : 0.014)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
        .overlay(alignment: .trailing) {
            if region == .sidebar {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.7))
                    .frame(width: 0.5)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.16), value: usesMaterial)
    }
}

private struct OrbitNativeVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let isEnabled: Bool
    let controlsWindowOpacity: Bool

    final class Coordinator {
        weak var configuredWindow: NSWindow?
        var appliedWindowOpacity: Bool?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = isEnabled ? .active : .inactive
        configureWindow(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = isEnabled ? .active : .inactive
        configureWindow(for: view, coordinator: context.coordinator)
    }

    private func configureWindow(for view: NSVisualEffectView, coordinator: Coordinator) {
        guard controlsWindowOpacity else { return }
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator, let window = view.window else { return }
            guard coordinator.configuredWindow !== window || coordinator.appliedWindowOpacity != self.isEnabled else {
                return
            }
            coordinator.configuredWindow = window
            coordinator.appliedWindowOpacity = self.isEnabled
            window.isOpaque = !self.isEnabled
            window.backgroundColor = self.isEnabled ? .clear : OrbitDesign.nsCanvas
        }
    }
}

enum OrbitDensity: String, CaseIterable, Identifiable {
    case compact
    case comfortable

    var id: Self { self }
    var title: String {
        self == .compact
            ? AppLanguage.text("紧凑", "Compact")
            : AppLanguage.text("舒适", "Comfortable")
    }
    var rowHeight: CGFloat { self == .compact ? 32 : 40 }
    var pageSpacing: CGFloat { self == .compact ? 12 : 18 }
}

enum OrbitTextRole: Sendable {
    case caption2
    case caption
    case callout
    case body
    case subheadline
    case headline
    case title3
    case title2

    func pointSize(base: CGFloat) -> CGFloat {
        switch self {
        case .caption2: max(9, base - 2)
        case .caption: max(10, base - 1)
        case .callout, .body: base
        case .subheadline, .headline: base + 1
        case .title3: base + 5
        case .title2: base + 9
        }
    }

    var defaultWeight: Font.Weight? {
        self == .headline ? .semibold : nil
    }
}

struct OrbitFontPalette: Sendable {
    let latin: String
    let cjk: String
    let baseSize: CGFloat

    @MainActor
    func font(_ role: OrbitTextRole, weight: Font.Weight? = nil) -> Font {
        OrbitTypography.ui(
            size: role.pointSize(base: baseSize),
            latin: latin,
            cjk: cjk,
            weight: weight ?? role.defaultWeight
        )
    }
}

private struct OrbitFontPaletteKey: EnvironmentKey {
    static let defaultValue = OrbitFontPalette(latin: "", cjk: "", baseSize: 13)
}

extension EnvironmentValues {
    var orbitFontPalette: OrbitFontPalette {
        get { self[OrbitFontPaletteKey.self] }
        set { self[OrbitFontPaletteKey.self] = newValue }
    }
}

private struct OrbitFontModifier: ViewModifier {
    @Environment(\.orbitFontPalette) private var palette
    let role: OrbitTextRole
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(palette.font(role, weight: weight))
    }
}

extension View {
    func orbitFont(_ role: OrbitTextRole, weight: Font.Weight? = nil) -> some View {
        modifier(OrbitFontModifier(role: role, weight: weight))
    }
}

@MainActor
enum OrbitTypography {
    private struct FontCacheKey: Hashable {
        let latin: String
        let cjk: String
        let sizeInTenths: Int
    }

    private static var resolvedFontCache: [FontCacheKey: NSFont] = [:]

    static func ui(
        size: CGFloat,
        latin: String,
        cjk: String,
        weight: Font.Weight? = nil
    ) -> Font {
        let cacheKey = FontCacheKey(
            latin: latin,
            cjk: cjk,
            sizeInTenths: Int((size * 10).rounded())
        )
        let resolved: NSFont
        if let cached = resolvedFontCache[cacheKey] {
            resolved = cached
        } else {
            let latinDescriptor = latin.isEmpty
                ? NSFont.systemFont(ofSize: size).fontDescriptor
                : NSFontDescriptor(fontAttributes: [.family: latin, .size: size])
            var attributes: [NSFontDescriptor.AttributeName: Any] = [:]
            if !cjk.isEmpty {
                let cjkDescriptor = NSFontDescriptor(fontAttributes: [.family: cjk, .size: size])
                attributes[.cascadeList] = [cjkDescriptor]
            }
            let descriptor = latinDescriptor.addingAttributes(attributes)
            resolved = NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
            if resolvedFontCache.count >= 64 {
                resolvedFontCache.removeAll(keepingCapacity: true)
            }
            resolvedFontCache[cacheKey] = resolved
        }
        let font = Font(resolved)
        if let weight {
            return font.weight(weight)
        }
        return font
    }

    static func activateConfiguredFamilies(latin: String, cjk: String) async {
        let activated = await OrbitFontActivator.shared.activate(families: [latin, cjk])
        if activated {
            resolvedFontCache.removeAll(keepingCapacity: true)
        }
    }
}

private actor OrbitFontActivator {
    static let shared = OrbitFontActivator()
    private var attemptedFamilies: Set<String> = []

    func activate(families: [String]) -> Bool {
        let requested = families.compactMap { family -> (String, String)? in
            let key = normalize(family)
            guard !key.isEmpty, attemptedFamilies.insert(key).inserted else { return nil }
            return (family, key)
        }
        guard !requested.isEmpty else { return false }

        let roots = [
            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Fonts", isDirectory: true),
            URL(fileURLWithPath: "/Library/Fonts", isDirectory: true)
        ].compactMap { $0 }
        let supportedExtensions = Set(["otf", "ttf", "ttc", "dfont"])
        var didActivate = false

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
                let fileKey = normalize(url.deletingPathExtension().lastPathComponent)
                guard requested.contains(where: { fileKey.contains($0.1) }) else { continue }
                var registrationError: Unmanaged<CFError>?
                if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError) {
                    didActivate = true
                }
                _ = registrationError?.takeRetainedValue()
            }
        }
        return didActivate
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}

struct OrbitPageReveal: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func orbitPageReveal() -> some View {
        modifier(OrbitPageReveal())
    }
}

struct OrbitInteractiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OrbitInteractiveButton(configuration: configuration)
    }
}

private struct OrbitInteractiveButton: View {
    let configuration: OrbitInteractiveButtonStyle.Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(isHovering ? OrbitDesign.primaryText.opacity(0.045) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isHovering ? OrbitDesign.separator.opacity(0.7) : .clear, lineWidth: 1)
            }
            .animation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

struct OrbitCard<Content: View>: View {
    @ViewBuilder let content: Content
    var emphasis: Bool = false

    init(emphasis: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.emphasis = emphasis
    }

    var body: some View {
        content
            .padding(16)
            .background(emphasis ? OrbitDesign.elevatedSurface : OrbitDesign.surface,
                        in: RoundedRectangle(cornerRadius: OrbitDesign.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: OrbitDesign.cornerRadius)
                    .stroke(OrbitDesign.separator.opacity(emphasis ? 0.95 : 0.75), lineWidth: 1)
            }
            .shadow(color: .black.opacity(emphasis ? 0.045 : 0), radius: emphasis ? 8 : 0, y: emphasis ? 2 : 0)
    }
}

struct OrbitIconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.27))
    }
}

struct OrbitStatusDot: View {
    let color: Color
    var animated = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay {
                if animated {
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 2)
                        .scaleEffect(1.8)
                }
            }
    }
}
