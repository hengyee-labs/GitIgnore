import SwiftUI

struct CommitStudioView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OrbitDesign.separator)
            if appState.commitStudio.isLoading {
                ProgressView("正在分析工作区区块…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
            Divider().overlay(OrbitDesign.separator)
            footer
        }
        .frame(minWidth: 980, minHeight: 650)
        .background(OrbitDesign.canvas)
        .interactiveDismissDisabled(appState.commitStudio.isCommitting)
    }

    private var header: some View {
        HStack(spacing: 12) {
            OrbitIconBadge(systemName: "square.stack.3d.up", color: OrbitDesign.accent, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("提交编排台").orbitFont(.title3, weight: .semibold)
                Text("把文件区块分配给多个提交，确认后一次安全生成提交序列。")
                    .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer()
            Button("关闭") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(appState.commitStudio.isCommitting)
        }
        .padding(.horizontal, 20).frame(height: 68)
    }

    private var content: some View {
        HStack(spacing: 0) {
            unassignedColumn.frame(minWidth: 330, idealWidth: 390, maxWidth: 440)
            Divider().overlay(OrbitDesign.separator)
            draftColumn
        }
    }

    private var unassignedColumn: some View {
        VStack(spacing: 0) {
            sectionHeader("未分配内容", count: appState.commitStudio.unassignedUnits.count)
            Divider().overlay(OrbitDesign.separator)
            if appState.commitStudio.unassignedUnits.isEmpty {
                ContentUnavailableView("内容已全部分配", systemImage: "checkmark.circle", description: Text("检查提交顺序后即可创建。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.commitStudio.unassignedUnits) { unit in
                            StudioUnitRow(unit: unit) { assign(unit.id, to: $0) }
                                .draggable(unit.id)
                        }
                    }.padding(8)
                }
            }
        }.background(OrbitDesign.canvas)
    }

    private var draftColumn: some View {
        VStack(spacing: 0) {
            HStack {
                sectionHeader("提交序列", count: appState.commitStudio.drafts.count)
                Button {
                    withAnimation(animation) { appState.commitStudio.drafts.append(CommitStudioDraft()) }
                } label: { Label("新增提交", systemImage: "plus") }
                .buttonStyle(.bordered).controlSize(.small)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .padding(.trailing, 14)
            }
            Divider().overlay(OrbitDesign.separator)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(appState.commitStudio.drafts.enumerated()), id: \.element.id) { index, draft in
                        StudioDraftCard(
                            index: index, draft: draft, units: units(for: draft),
                            canDelete: appState.commitStudio.drafts.count > 1,
                            onMessageChange: { updateMessage($0, draftID: draft.id) },
                            onRemoveUnit: { remove($0, from: draft.id) },
                            onDelete: { deleteDraft(draft.id) },
                            onMoveUp: { moveDraft(from: index, offset: -1) },
                            onMoveDown: { moveDraft(from: index, offset: 1) }
                        )
                        .dropDestination(for: String.self) { ids, _ in
                            ids.forEach { assign($0, to: draft.id) }
                            return !ids.isEmpty
                        }
                    }
                }.padding(14)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            let remaining = appState.commitStudio.unassignedUnits.count
            Image(systemName: remaining == 0 ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(remaining == 0 ? OrbitDesign.accent : OrbitDesign.amber)
            Text(remaining == 0 ? "全部内容已分配" : "还有 \(remaining) 个区块未分配")
                .orbitFont(.caption, weight: .medium)
            Spacer()
            Text("将按从上到下的顺序创建提交").orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
            Button("按顺序创建提交") { Task { await appState.executeCommitStudio() } }
                .buttonStyle(.borderedProminent).tint(OrbitDesign.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(remaining != 0 || appState.commitStudio.isCommitting || !draftsAreValid)
        }.padding(.horizontal, 18).frame(height: 58)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title).orbitFont(.caption, weight: .semibold)
            Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(OrbitDesign.secondaryText)
            Spacer()
        }.padding(.horizontal, 14).frame(height: 44)
    }

    private var animation: Animation { reduceMotion ? .easeOut(duration: 0.1) : OrbitDesign.feedbackAnimation }
    private var draftsAreValid: Bool {
        appState.commitStudio.drafts.allSatisfy {
            !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.unitIDs.isEmpty
        }
    }
    private func units(for draft: CommitStudioDraft) -> [CommitStudioUnit] {
        appState.commitStudio.units.filter { draft.unitIDs.contains($0.id) }
    }
    private func assign(_ unitID: String, to draftID: UUID) {
        withAnimation(animation) {
            for index in appState.commitStudio.drafts.indices { appState.commitStudio.drafts[index].unitIDs.remove(unitID) }
            guard let index = appState.commitStudio.drafts.firstIndex(where: { $0.id == draftID }) else { return }
            appState.commitStudio.drafts[index].unitIDs.insert(unitID)
        }
    }
    private func remove(_ unitID: String, from draftID: UUID) {
        withAnimation(animation) {
            guard let index = appState.commitStudio.drafts.firstIndex(where: { $0.id == draftID }) else { return }
            appState.commitStudio.drafts[index].unitIDs.remove(unitID)
        }
    }
    private func updateMessage(_ message: String, draftID: UUID) {
        guard let index = appState.commitStudio.drafts.firstIndex(where: { $0.id == draftID }) else { return }
        appState.commitStudio.drafts[index].message = message
    }
    private func deleteDraft(_ id: UUID) {
        withAnimation(animation) { appState.commitStudio.drafts.removeAll { $0.id == id } }
    }
    private func moveDraft(from index: Int, offset: Int) {
        let destination = index + offset
        guard appState.commitStudio.drafts.indices.contains(destination) else { return }
        withAnimation(animation) { appState.commitStudio.drafts.swapAt(index, destination) }
    }
}

private struct StudioUnitRow: View {
    let unit: CommitStudioUnit
    let assign: (UUID) -> Void
    @Environment(AppState.self) private var appState
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: unit.isWholeFile ? "doc" : "text.line.first.and.arrowtriangle.forward")
                .foregroundStyle(OrbitDesign.secondaryText).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.path).orbitFont(.caption, weight: .medium).lineLimit(1)
                Text(unit.title).font(.caption2.monospaced()).foregroundStyle(OrbitDesign.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text("+\(unit.addedLines) −\(unit.removedLines)").font(.caption2.monospacedDigit()).foregroundStyle(OrbitDesign.secondaryText)
            Menu {
                ForEach(Array(appState.commitStudio.drafts.enumerated()), id: \.element.id) { index, draft in
                    Button("提交 \(index + 1) · \(draft.message.isEmpty ? "未命名" : draft.message)") { assign(draft.id) }
                }
            } label: { Image(systemName: "arrow.right.circle").frame(width: 26, height: 26) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
        .padding(.horizontal, 9).frame(minHeight: 42).contentShape(Rectangle())
        .background(OrbitDesign.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(unit.path)，新增 \(unit.addedLines) 行，删除 \(unit.removedLines) 行")
    }
}

private struct StudioDraftCard: View {
    let index: Int
    let draft: CommitStudioDraft
    let units: [CommitStudioUnit]
    let canDelete: Bool
    let onMessageChange: (String) -> Void
    let onRemoveUnit: (String) -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(index + 1)").font(.caption.bold()).frame(width: 24, height: 24)
                    .background(OrbitDesign.accent.opacity(0.12), in: Circle()).foregroundStyle(OrbitDesign.accent)
                TextField("提交摘要", text: Binding(get: { draft.message }, set: { onMessageChange($0) }))
                    .textFieldStyle(.plain).orbitFont(.callout, weight: .semibold)
                Spacer()
                Button(action: onMoveUp) { Image(systemName: "chevron.up") }.disabled(index == 0)
                Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                if canDelete { Button(role: .destructive, action: onDelete) { Image(systemName: "trash") } }
            }.buttonStyle(.plain).foregroundStyle(OrbitDesign.secondaryText).padding(11)
            Divider().overlay(OrbitDesign.separator)
            if units.isEmpty {
                Text("拖入左侧区块，或使用区块右侧的分配按钮")
                    .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(units) { unit in
                        HStack(spacing: 8) {
                            Text(unit.path).orbitFont(.caption).lineLimit(1)
                            Spacer()
                            Text(unit.isWholeFile ? "文件" : "区块").orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
                            Button { onRemoveUnit(unit.id) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).foregroundStyle(OrbitDesign.secondaryText)
                        }.padding(.horizontal, 11).frame(height: 34)
                    }
                }
            }
        }
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(OrbitDesign.separator, lineWidth: 1) }
        .accessibilityElement(children: .contain).accessibilityLabel("第 \(index + 1) 个提交")
    }
}
