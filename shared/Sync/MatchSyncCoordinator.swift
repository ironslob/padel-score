import Foundation
import WatchConnectivity

/// Bidirectional sync of active match + archive between Watch and iPhone.
/// Watch is authoritative during live scoring; iPhone applies remote snapshots.
/// History deletion runs the other way: the iPhone owns it, and the Watch prunes
/// its own archive to match.
@MainActor
public final class MatchSyncCoordinator: NSObject, ObservableObject {
    public static let activeKey = "activeMatchJSON"
    public static let archiveKey = "archiveJSON"
    public static let deletedKey = "deletedMatchIDsJSON"

    private let service: MatchService
    private let session: WCSession?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let isWatch: Bool

    public init(service: MatchService, isWatch: Bool) {
        self.service = service
        self.isWatch = isWatch
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        if WCSession.isSupported() {
            self.session = WCSession.default
        } else {
            self.session = nil
        }

        super.init()

        if let session {
            session.delegate = self
            session.activate()
        }

        service.onSyncNeeded { [weak self] active, archive, deleted in
            self?.push(active: active, archive: archive, deleted: deleted)
        }
    }

    public func push(active: MatchState?, archive: [MatchState], deleted: Set<UUID>) {
        guard let session, session.activationState == .activated else { return }

        var context: [String: Any] = [:]
        do {
            if let active {
                context[Self.activeKey] = try encoder.encode(active)
            } else {
                context[Self.activeKey] = Data()
            }
            context[Self.archiveKey] = try encoder.encode(archive)
            // Sent in full rather than as a delta, so a Watch that was unreachable at
            // deletion time still catches up on its next context update.
            context[Self.deletedKey] = try encoder.encode(Array(deleted))
            try session.updateApplicationContext(context)

            #if os(watchOS)
            if session.isReachable {
                session.sendMessage(context, replyHandler: nil, errorHandler: nil)
            }
            #else
            if session.isReachable {
                session.sendMessage(context, replyHandler: nil, errorHandler: nil)
            }
            #endif
        } catch {
            // Non-fatal: local scoring continues offline.
        }
    }

    private func apply(context: [String: Any]) {
        let deleted: Set<UUID>
        if let data = context[Self.deletedKey] as? Data, !data.isEmpty {
            deleted = Set((try? decoder.decode([UUID].self, from: data)) ?? [])
        } else {
            deleted = []
        }

        // Watch remains authoritative for live scoring, so it takes deletions from the
        // phone and ignores everything else in the payload.
        guard !isWatch else {
            service.applyRemoteDeletions(deleted)
            return
        }

        let active: MatchState?
        if let data = context[Self.activeKey] as? Data, !data.isEmpty {
            active = try? decoder.decode(MatchState.self, from: data)
        } else {
            active = nil
        }

        let archive: [MatchState]
        if let data = context[Self.archiveKey] as? Data, !data.isEmpty {
            archive = (try? decoder.decode([MatchState].self, from: data)) ?? []
        } else {
            archive = []
        }

        service.applyRemoteSnapshot(active: active, archive: archive)
    }
}

extension MatchSyncCoordinator: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if activationState == .activated {
                self.push(
                    active: self.service.activeMatch,
                    archive: self.service.archivedMatches,
                    deleted: self.service.deletedMatchIDs
                )
            }
        }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    nonisolated public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            self.apply(context: applicationContext)
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in
            self.apply(context: message)
        }
    }
}
