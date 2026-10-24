import SwiftUI

struct InspectorDisplaySettings: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Set<String>()
    private var hiddenPending: Set<String> { m.inspectorPatch.effective.subtracting(chosen) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tags to Display in Tag Inspector").font(.title2.bold())
            Text("Choose editable tag fields to show. Hiding a field does not delete its tags or change workspace columns.").foregroundStyle(.secondary)
            HStack {
                Button("Select All") { chosen = Set(TagVisibility.tags) }
                Button("Select None") { chosen = [] }
                Button("Select from Purge configuration") { chosen = TagVisibility.inspectorFields(fromPurge: m.purgeFields) }
            }
            Text("Select from Purge configuration shows tags not selected for purge. It copies the choice once; later changes remain independent.").font(.callout).foregroundStyle(.secondary)
            List(TagVisibility.tags, id: \.self) { field in
                Toggle(field, isOn: Binding(get: { chosen.contains(field) }, set: { enabled in
                    if enabled { chosen.insert(field) } else { chosen.remove(field) }
                }))
            }
            if !hiddenPending.isEmpty {
                Label("Save or discard pending edits before hiding: " + hiddenPending.sorted().joined(separator: ", ") + ". Cancel this dialog to return to the inspector.", systemImage: "exclamationmark.triangle").fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("\(chosen.count) tags displayed").font(.callout)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") { m.inspectorDisplayedFields = chosen; dismiss() }
                    .buttonStyle(.borderedProminent).disabled(!hiddenPending.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(minWidth: 680, idealWidth: 720, maxWidth: .infinity, minHeight: 480, idealHeight: 620, maxHeight: .infinity).background(ResizableReviewSheet())
            .onAppear { chosen = m.inspectorDisplayedFields }
    }
}

struct WorkspaceColumnSettings: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Set<String>()
    private var groups: (shown: [String], hidden: [String]) { TagVisibility.groups(inspector: m.inspectorDisplayedFields) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Customize Columns").font(.title2.bold())
            Text("Column visibility is independent of the Tag Inspector. Tag choices are alphabetized within each group. Filename and selection remain available for identifying files.").foregroundStyle(.secondary)
            HStack {
                Button("Select All") { chosen = TagVisibility.columnChoices }
                Button("Select None") { chosen = ["Filename"] }
                Button("Restore Defaults") { chosen = TagVisibility.defaultColumns }
            }
            List {
                Section("File columns") {
                    Toggle("Filename (always shown)", isOn: .constant(true)).disabled(true)
                    choice("Status")
                }
                Section("Shown in Tag Inspector") {
                    if groups.shown.isEmpty { Text("No tags are shown in the inspector.").foregroundStyle(.secondary) }
                    ForEach(groups.shown, id: \.self) { choice($0) }
                }
                Section("Hidden from Tag Inspector") {
                    if groups.hidden.isEmpty { Text("All supported tags are shown in the inspector.").foregroundStyle(.secondary) }
                    ForEach(groups.hidden, id: \.self) { choice($0) }
                }
            }
            HStack {
                Text("\(chosen.count) columns displayed, plus selection").font(.callout)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") { m.workspaceColumns = chosen.union(["Filename"]); dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(minWidth: 640, idealWidth: 680, maxWidth: .infinity, minHeight: 480, idealHeight: 650, maxHeight: .infinity).background(ResizableReviewSheet())
            .onAppear { chosen = m.workspaceColumns }
    }
    private func choice(_ field: String) -> some View {
        Toggle(field, isOn: Binding(get: { chosen.contains(field) }, set: { enabled in
            if enabled { chosen.insert(field) } else { chosen.remove(field) }
        }))
    }
}
