import SwiftUI

@main
struct TomatoTimerApp: App {
    @StateObject private var viewModel = TimerViewModel(
        notificationService: UserNotificationService()
    )

    var body: some Scene {
        MenuBarExtra {
            TimerMenuView(viewModel: viewModel)
        } label: {
            HStack(spacing: 4) {
                Image("TomatoMenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                if let menuBarTitle = viewModel.menuBarTitle {
                    Text(menuBarTitle)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
