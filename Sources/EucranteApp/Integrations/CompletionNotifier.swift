import Foundation
@preconcurrency import UserNotifications

actor CompletionNotifier {
  func requestAuthorization() async -> Bool {
    (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]))
      ?? false
  }

  func send(filename: String, preset: String) async {
    let center = UNUserNotificationCenter.current()
    let content = UNMutableNotificationContent()
    content.title = "Eucrante finished saving"
    content.body = "\(filename) · \(preset)"
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    try? await center.add(request)
  }
}
