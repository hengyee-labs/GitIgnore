import AppKit
import SwiftUI

enum MergeEditorPaneRole {
    case current
    case result
    case incoming
}

@MainActor
final class MergeScrollSynchronizer {
    private let scrollViews = NSHashTable<NSScrollView>.weakObjects()
    private var isBroadcasting = false
    private var lastOffsetCallback = Date.distantPast
    var onOffset: ((CGFloat) -> Void)?

    func register(_ scrollView: NSScrollView) {
        scrollViews.add(scrollView)
    }

    func unregister(_ scrollView: NSScrollView) {
        scrollViews.remove(scrollView)
    }

    func broadcast(offset: CGFloat, source: NSScrollView) {
        guard !isBroadcasting else { return }
        isBroadcasting = true
        for scrollView in scrollViews.allObjects where scrollView !== source {
            var origin = scrollView.contentView.bounds.origin
            origin.y = max(0, offset)
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        isBroadcasting = false

        let now = Date()
        if now.timeIntervalSince(lastOffsetCallback) >= 0.08 {
            lastOffsetCallback = now
            onOffset?(offset)
        }
    }
}

struct MergeCodeEditor: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let role: MergeEditorPaneRole
    var focusLine: Int?
    var highlightedLines: ClosedRange<Int>?
    var synchronizer: MergeScrollSynchronizer?
    @Binding private var synchronizedOffset: CGFloat

    init(
        text: Binding<String>,
        isEditable: Bool,
        role: MergeEditorPaneRole,
        focusLine: Int? = nil,
        highlightedLines: ClosedRange<Int>? = nil,
        synchronizer: MergeScrollSynchronizer? = nil,
        synchronizedOffset: Binding<CGFloat> = .constant(0)
    ) {
        _text = text
        self.isEditable = isEditable
        self.role = role
        self.focusLine = focusLine
        self.highlightedLines = highlightedLines
        self.synchronizer = synchronizer
        _synchronizedOffset = synchronizedOffset
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = isEditable
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.insertionPointColor = role == .result ? .systemPurple : .systemGreen
        textView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        scrollView.documentView = textView

        let ruler = MergeLineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.ruler = ruler
        synchronizer?.register(scrollView)
        context.coordinator.startObservingScroll()
        context.coordinator.applyStyles(force: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        textView.isEditable = isEditable
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        var textChanged = false
        if textView.string != text, !context.coordinator.isApplyingTextChange {
            let selection = textView.selectedRange()
            context.coordinator.isApplyingTextChange = true
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            context.coordinator.isApplyingTextChange = false
            textChanged = true
        }
        context.coordinator.applyStyles(force: textChanged)
        context.coordinator.scrollToFocusLineIfNeeded(focusLine)
        context.coordinator.applySynchronizedOffset(synchronizedOffset)
        context.coordinator.ruler?.needsDisplay = true
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.parent.synchronizer?.unregister(nsView)
        coordinator.stopObservingScroll()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MergeCodeEditor
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        weak var ruler: MergeLineNumberRulerView?
        var isApplyingTextChange = false
        private var isApplyingScroll = false
        private var lastFocusLine: Int?
        private var lastHighlightedLines: ClosedRange<Int>?
        private var scrollObserver: NSObjectProtocol?
        private var styleWorkItem: DispatchWorkItem?

        init(parent: MergeCodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard parent.isEditable, !isApplyingTextChange, let textView else { return }
            parent.text = textView.string
            scheduleStyleRefresh()
            ruler?.needsDisplay = true
        }

        func startObservingScroll() {
            guard let scrollView else { return }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isApplyingScroll, let scrollView = self.scrollView else { return }
                    let offset = scrollView.contentView.bounds.origin.y
                    if let synchronizer = self.parent.synchronizer {
                        synchronizer.broadcast(offset: offset, source: scrollView)
                    } else {
                        self.parent.synchronizedOffset = offset
                    }
                    self.ruler?.needsDisplay = true
                }
            }
        }

        func stopObservingScroll() {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            styleWorkItem?.cancel()
        }

        @MainActor
        func applySynchronizedOffset(_ offset: CGFloat) {
            guard parent.synchronizer == nil else { return }
            guard let scrollView, abs(scrollView.contentView.bounds.origin.y - offset) > 1 else { return }
            isApplyingScroll = true
            var origin = scrollView.contentView.bounds.origin
            origin.y = max(0, offset)
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingScroll = false
        }

        @MainActor
        func scrollToFocusLineIfNeeded(_ line: Int?) {
            guard let line, line != lastFocusLine, let textView else { return }
            lastFocusLine = line
            let location = characterLocation(forLine: line, in: textView.string)
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        }

        @MainActor
        func applyStyles(force: Bool) {
            guard let textView, let storage = textView.textStorage else { return }
            let highlightChanged = lastHighlightedLines != parent.highlightedLines
            guard force || highlightChanged else { return }
            lastHighlightedLines = parent.highlightedLines
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)

            if storage.length <= 2_000_000 {
                let source = storage.string as NSString
                source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: .byLines) { substring, range, _, _ in
                    guard let substring else { return }
                    if substring.hasPrefix("<<<<<<<") || substring.hasPrefix("|||||||")
                        || substring.hasPrefix("=======") || substring.hasPrefix(">>>>>>>") {
                        storage.addAttributes([
                            .foregroundColor: NSColor.secondaryLabelColor,
                            .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.10)
                        ], range: range)
                    }
                }
            }
            if let lines = parent.highlightedLines {
                let range = characterRange(for: lines, in: storage.string)
                storage.addAttribute(.backgroundColor, value: highlightColor(), range: range)
            }
            storage.endEditing()
        }

        private func scheduleStyleRefresh() {
            styleWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.applyStyles(force: true) }
            }
            styleWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
        }

        private func highlightColor() -> NSColor {
            switch parent.role {
            case .current: NSColor.systemBlue.withAlphaComponent(0.09)
            case .result: NSColor.systemPurple.withAlphaComponent(0.11)
            case .incoming: NSColor.systemGreen.withAlphaComponent(0.09)
            }
        }

        private func characterLocation(forLine line: Int, in text: String) -> Int {
            let source = text as NSString
            var location = 0
            for _ in 0..<max(line, 0) {
                let range = source.lineRange(for: NSRange(location: min(location, source.length), length: 0))
                location = NSMaxRange(range)
                if location >= source.length { break }
            }
            return min(location, source.length)
        }

        private func characterRange(for lines: ClosedRange<Int>, in text: String) -> NSRange {
            let start = characterLocation(forLine: lines.lowerBound, in: text)
            let end = characterLocation(forLine: lines.upperBound + 1, in: text)
            return NSRange(location: start, length: max(0, end - start))
        }
    }
}

final class MergeLineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 42
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        let visible = textView.enclosingScrollView?.contentView.bounds ?? .zero
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let source = textView.string as NSString
        var lineNumber = 1
        var cursor = 0
        while cursor < characterRange.location {
            cursor = NSMaxRange(source.lineRange(for: NSRange(location: cursor, length: 0)))
            lineNumber += 1
        }
        while cursor < NSMaxRange(characterRange), cursor < source.length {
            let glyph = layoutManager.glyphIndexForCharacter(at: cursor)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            lineRect.origin.y += textView.textContainerOrigin.y - visible.origin.y
            let label = "\(lineNumber)" as NSString
            label.draw(
                in: NSRect(x: 2, y: lineRect.minY, width: ruleThickness - 8, height: lineRect.height),
                withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: rightAlignedParagraphStyle
                ]
            )
            cursor = NSMaxRange(source.lineRange(for: NSRange(location: cursor, length: 0)))
            lineNumber += 1
        }
    }

    private var rightAlignedParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }
}
