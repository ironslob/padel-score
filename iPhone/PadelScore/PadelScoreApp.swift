import SwiftUI

@main
struct PadelScoreApp: App {
    @StateObject private var appModel = PhoneAppModel()

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(appModel.service)
                .onChange(of: appModel.service.activeMatch) { _, match in
                    appModel.liveActivityManager.sync(with: match)
                }
                .onAppear {
                    appModel.liveActivityManager.sync(with: appModel.service.activeMatch)
                }
        }
    }
}

@MainActor
final class PhoneAppModel: ObservableObject {
    let service: MatchService
    let sync: MatchSyncCoordinator
    let liveActivityManager = MatchLiveActivityManager()

    init() {
        let service = MatchService(store: FileMatchStore())
        self.service = service
        self.sync = MatchSyncCoordinator(service: service, isWatch: false)
    }
}
