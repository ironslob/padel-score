import SwiftUI

@main
struct PadelScoreApp: App {
    @StateObject private var appModel = PhoneAppModel()

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(appModel.service)
        }
    }
}

@MainActor
final class PhoneAppModel: ObservableObject {
    let service: MatchService
    let sync: MatchSyncCoordinator

    init() {
        let service = MatchService(store: FileMatchStore())
        self.service = service
        self.sync = MatchSyncCoordinator(service: service, isWatch: false)
    }
}
