import SwiftUI

@main
struct MATEApp: App {
    @StateObject private var store = MateStore()
    @StateObject private var engine = MateInferenceEngine()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            MateRootView()
                .environmentObject(store)
                .environmentObject(engine)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .tint(MateStyle.indigo)
        }
    }
}

enum MateStyle {
    static let indigo = Color(red: 0.27, green: 0.31, blue: 0.82)
    static let card = Color(.secondarySystemGroupedBackground)
    static let canvas = Color(.systemGroupedBackground)
}
