import SwiftUI

#if !arch(arm64)
  #error("Eucrante supports Apple silicon only. Build for arm64.")
#endif

@main
@MainActor
struct EucranteApp: App {
  @StateObject private var model: AppModel

  init() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
        do {
          let preview = try PreviewFixture.makeModel()
          _model = StateObject(wrappedValue: preview)
          return
        } catch { fatalError("Unable to create isolated UI preview: \(error)") }
      }
    #endif
    _model = StateObject(wrappedValue: AppModel())
  }

  var body: some Scene {
    Window("Eucrante", id: "main") {
      AppShellView(model: model)
        .navigationSubtitle(previewSubtitle)
        .frame(minWidth: 720, minHeight: 520)
        .onOpenURL { model.handleIncomingURL($0) }
    }
    .defaultSize(width: 880, height: 640)
    .commands {
      CommandMenu("Save") {
        Button("Save Link") {
          Task { await model.submit() }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!model.canSubmit)

        Button("Focus Link Field") {
          model.focusRequestID = UUID()
        }
        .keyboardShortcut("l", modifiers: .command)
      }
    }

    Settings {
      SettingsView(model: model)
        .frame(width: 600, height: 500)
    }
  }

  private var previewSubtitle: String {
    #if DEBUG
      return ProcessInfo.processInfo.arguments.contains("--ui-preview") ? "UI Preview" : ""
    #else
      return ""
    #endif
  }
}
