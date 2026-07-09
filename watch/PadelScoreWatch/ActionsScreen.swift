import SwiftUI

struct ActionsScreen: View {
    @EnvironmentObject private var service: MatchService
    let match: MatchState

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

            Button(role: .destructive) {
                confirmDiscard = true
            } label: {
                Label("Discard Match", systemImage: "trash")
            }
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
