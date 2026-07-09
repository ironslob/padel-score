import SwiftUI

@main
struct PadelScoreWatchApp: App {
    @StateObject private var appModel: WatchAppModel

    init() {
        _appModel = StateObject(wrappedValue: WatchAppModel())
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(appModel.service)
                .environmentObject(appModel.sessionCoordinator)
        }
    }
}

@MainActor
final class WatchAppModel: ObservableObject {
    let service: MatchService
    let sync: MatchSyncCoordinator
    let sessionCoordinator: MatchSessionCoordinator

    init() {
        let service = MatchService(store: FileMatchStore())
        self.service = service
        self.sync = MatchSyncCoordinator(service: service, isWatch: true)
        self.sessionCoordinator = MatchSessionCoordinator(service: service)
    }
}
