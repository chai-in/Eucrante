import SwiftUI

@main
struct EucranteApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      AppShellView(model: model)
        .frame(minWidth: 680, minHeight: 460)
    }
    .defaultSize(width: 820, height: 560)
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
        .frame(width: 560, height: 420)
    }
  }
}
