import SwiftUI

struct ActionsScreen: View {
    @EnvironmentObject private var service: MatchService
    let match: MatchState

    @State private var confirmFinish = false
    @State private var confirmEndEarly = false
    @State private var confirmDiscard = false
    @State private var showDuringPlayHelp = false

    var body: some View {
        List {
            Button {
                showDuringPlayHelp = true
            } label: {
                Label("During play tips", systemImage: "questionmark.circle")
            }

            Button {
                service.undoLastPoint()
            } label: {
                Label("Undo Last Point", systemImage: "arrow.uturn.backward")
            }
            .disabled(!service.canUndo)

            Button {
                confirmFinish = true
            } label: {
                Label("Finish Match", systemImage: "checkmark.circle")
            }

            Button {
                confirmEndEarly = true
            } label: {
                Label("End Match Early", systemImage: "stop.circle")
            }

            Button(role: .destructive) {
                confirmDiscard = true
            } label: {
                Label("Discard Match", systemImage: "trash")
            }
        }
        .confirmationDialog("Finish this match?", isPresented: $confirmFinish) {
            Button("Finish Match", role: .destructive) { service.finishMatch() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("End match early? Score will be kept.", isPresented: $confirmEndEarly) {
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
