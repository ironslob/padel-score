import SwiftUI

struct ActionsScreen: View {
    @EnvironmentObject private var service: MatchService
    let match: MatchState

    @State private var confirmEndMatch = false
    @State private var confirmEndEarly = false
    @State private var confirmDiscard = false
    @State private var showDuringPlayHelp = false

    var body: some View {
        List {
            Button {
                service.undoLastPoint()
            } label: {
                Label("Undo Last Point", systemImage: "arrow.uturn.backward")
            }
            .disabled(!service.canUndo)

            // Only between sets, and only while nothing has been played into the new
            // one — the same window the set summary offers it in, for when that
            // dismissed itself before anyone reached the watch.
            if match.canChooseNewServer {
                Button {
                    service.requestServerSelection()
                } label: {
                    Label("New Serve", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Button(role: .destructive) {
                confirmEndMatch = true
            } label: {
                Label("End Match", systemImage: "flag.checkered")
            }

            Button(role: .destructive) {
                confirmEndEarly = true
            } label: {
                Label("End Match Early", systemImage: "stop.circle")
            }

            MatchPreferenceToggles(match: match)

            Button {
                showDuringPlayHelp = true
            } label: {
                Label("During play tips", systemImage: "questionmark.circle")
            }

            Button(role: .destructive) {
                confirmDiscard = true
            } label: {
                Label("Discard Match", systemImage: "trash")
            }
        }
        .confirmationDialog("End this match?", isPresented: $confirmEndMatch) {
            Button("End Match", role: .destructive) { service.finishMatch() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("End match early? The current score is kept.", isPresented: $confirmEndEarly) {
            Button("End Early", role: .destructive) { service.endMatchEarly() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Discard match? History will be deleted.", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { service.discardMatch() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showDuringPlayHelp) {
            DuringPlayHelpView()
        }
    }
}
