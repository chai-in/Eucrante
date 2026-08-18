import SwiftUI

struct AppShellView: View {
  enum Section: String, CaseIterable, Identifiable {
    case save = "Save"
    case queue = "Queue"

    var id: Self { self }
    var icon: String { self == .save ? "square.and.arrow.down" : "list.bullet.rectangle" }
  }

  @ObservedObject var model: AppModel
  @State private var selection: Section? = .save

  var body: some View {
    NavigationSplitView {
      List(Section.allCases, selection: $selection) { section in
        Label(section.rawValue, systemImage: section.icon)
          .tag(section)
      }
      .navigationTitle("Eucrante")
      .navigationSplitViewColumnWidth(min: 150, ideal: 175, max: 220)
    } detail: {
      switch selection ?? .save {
      case .save:
        SaveView(model: model)
      case .queue:
        QueueView(model: model)
      }
    }
    .tint(.eucranteAccent)
    .toolbar {
      ToolbarItem {
        SettingsLink {
          Label("Settings", systemImage: "gearshape")
        }
      }
    }
    .alert(
      "Couldn’t Save",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      ),
      actions: {
        Button("OK", role: .cancel) { model.errorMessage = nil }
      },
      message: {
        Text(model.errorMessage ?? "An unknown error occurred.")
      }
    )
  }
}
