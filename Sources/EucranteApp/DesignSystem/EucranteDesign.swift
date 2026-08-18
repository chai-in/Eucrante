import SwiftUI

extension Color {
  static let eucranteAccent = Color(red: 0.16, green: 0.38, blue: 0.85)
}

struct EucranteCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(24)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(.quaternary, lineWidth: 1)
      }
  }
}

extension View {
  func eucranteCard() -> some View { modifier(EucranteCardModifier()) }
}
