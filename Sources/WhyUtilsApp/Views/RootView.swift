import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let panelShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        ZStack {
            panelShape
                .fill(Color.whyPanelBackground)
                .overlay(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.teal.opacity(0.10), Color.black.opacity(0.14), Color.clear]
                            : [Color.teal.opacity(0.08), Color.white.opacity(0.20), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    panelShape
                        .stroke(Color.whyPanelBorder, lineWidth: 1)
                )

            Group {
                switch coordinator.route {
                case .launcher:
                    LauncherView()
                case .tool(let tool):
                    ToolContainerView(tool: tool)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(coordinator.route == .launcher ? 0 : 14)
        }
        .clipShape(panelShape)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
