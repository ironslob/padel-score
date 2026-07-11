#if os(iOS)
import ActivityKit
import Foundation

@MainActor
public final class MatchLiveActivityManager: ObservableObject {
    private var activeMatchID: UUID?
    private var activity: Activity<MatchActivityAttributes>?

    public init() {}

    public func sync(with match: MatchState?) {
        guard let action = MatchLiveActivityLifecycle.action(
            previousMatchID: activeMatchID,
            match: match
        ) else {
            return
        }

        switch action {
        case .start(let match):
            start(match)
        case .update(let match):
            update(match)
        case .end(let dismissImmediately):
            end(dismissImmediately: dismissImmediately)
        }
    }

    private func start(_ match: MatchState) {
        end(dismissImmediately: true)

        let attributes = MatchActivityAttributes(matchID: match.id)
        let content = ActivityContent(
            state: MatchActivityAttributes.ContentState(from: match),
            staleDate: nil
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            activeMatchID = match.id
        } catch {
            activity = nil
            activeMatchID = nil
        }
    }

    private func update(_ match: MatchState) {
        guard let activity else {
            start(match)
            return
        }

        let content = ActivityContent(
            state: MatchActivityAttributes.ContentState(from: match),
            staleDate: nil
        )
        Task {
            await activity.update(content)
        }
        activeMatchID = match.id
    }

    private func end(dismissImmediately: Bool) {
        guard let activity else {
            activeMatchID = nil
            return
        }

        let policy: ActivityUIDismissalPolicy = dismissImmediately ? .immediate : .default
        Task {
            await activity.end(nil, dismissalPolicy: policy)
        }
        self.activity = nil
        activeMatchID = nil
    }
}
#endif
