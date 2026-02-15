import SwiftUI

@main
struct AgentOSApp: App {
    @State private var viewModel = DashboardViewModel()

    var body: some Scene {
        WindowGroup("Agent OS") {
            RootDashboardView(viewModel: viewModel)
                .frame(minWidth: 1_280, minHeight: 820)
        }
        .windowResizability(.contentMinSize)
    }
}
