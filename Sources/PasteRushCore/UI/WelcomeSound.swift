import AppKit
import Foundation

/// Short first-run celebration chime (BoringNotch-style welcome flourish).
enum WelcomeSound {
    private static var retained: NSSound?

    static func play() {
        if let url = Bundle.main.url(forResource: "welcome", withExtension: "aiff", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: "welcome", withExtension: "aiff")
        {
            let sound = NSSound(contentsOf: url, byReference: true)
            retained = sound
            sound?.play()
            return
        }
        // Fallback if the asset wasn't bundled
        NSSound(named: "Glass")?.play()
    }
}
