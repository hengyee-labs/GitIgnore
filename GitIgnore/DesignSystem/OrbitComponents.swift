import SwiftUI

enum OrbitMotion {
    static let pageDuration = 0.17
    static let inspectorDuration = 0.18
    static let reducedDuration = 0.08

    static func page(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? reducedDuration : pageDuration)
    }

    static func inspector(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? reducedDuration : inspectorDuration)
    }
}

struct OrbitPageHeader<Actions: View, Accessory: View>: View {
    let title: String
    let subtitle: String
    let systemName: String
    let tint: Color
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        subtitle: String,
        systemName: String,
        tint: Color = OrbitDesign.accent,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemName = systemName
        self.tint = tint
        self.actions = actions
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .orbitFont(.title2, weight: .bold)
                        .foregroundStyle(OrbitDesign.primaryText)
                    Text(subtitle)
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 16)
                actions()
            }

            accessory()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(OrbitDesign.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OrbitDesign.separator).frame(height: 1)
        }
    }
}

extension OrbitPageHeader where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String,
        systemName: String,
        tint: Color = OrbitDesign.accent,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemName: systemName,
            tint: tint,
            actions: actions,
            accessory: { EmptyView() }
        )
    }
}

struct OrbitSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(OrbitDesign.tertiaryText)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(OrbitDesign.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguage.text("清除搜索", "Clear Search"))
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(OrbitDesign.separator, lineWidth: 1) }
    }
}

struct OrbitEmptyState<Actions: View>: View {
    let title: String
    let message: String
    let systemName: String
    let tint: Color
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 16) {
            OrbitIconBadge(systemName: systemName, color: tint, size: 52)
            VStack(spacing: 6) {
                Text(title).orbitFont(.title3, weight: .bold)
                Text(message)
                    .orbitFont(.subheadline)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            actions()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension OrbitEmptyState where Actions == EmptyView {
    init(title: String, message: String, systemName: String, tint: Color = OrbitDesign.accent) {
        self.init(title: title, message: message, systemName: systemName, tint: tint) { EmptyView() }
    }
}
