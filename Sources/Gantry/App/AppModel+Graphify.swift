import Foundation

extension AppModel {
    func showGraphify() {
        commandPalettePresented = false
        mainDestination = .graphify
    }

    func hideGraphify() {
        mainDestination = .workspace
    }
}
