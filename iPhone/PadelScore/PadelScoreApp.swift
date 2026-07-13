import SwiftUI

@main
struct PadelScoreApp: App {
    @StateObject private var appModel = PhoneAppModel()

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(appModel)
                .environmentObject(appModel.service)
                .onChange(of: appModel.service.activeMatch) { _, match in
                    appModel.liveActivityManager.sync(with: match)
                }
        }
    }
}

@MainActor
final class PhoneAppModel: ObservableObject {
    let service: MatchService
    private(set) var sync: MatchSyncCoordinator?
    let liveActivityManager = MatchLiveActivityManager()

    init() {
        self.service = MatchService(store: FileMatchStore(), autoRestore: false)
    }

    func bootstrap() async {
        await service.restore()
        if sync == nil {
            sync = MatchSyncCoordinator(service: service, isWatch: false)
        }
        liveActivityManager.sync(with: service.activeMatch)
    }
}
