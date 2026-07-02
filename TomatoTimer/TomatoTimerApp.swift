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
                Image(systemName: "hourglass")
                if let menuBarTitle = viewModel.menuBarTitle {
                    Text(menuBarTitle)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
