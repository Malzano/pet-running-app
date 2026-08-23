import SwiftUI
import WidgetKit

@main
struct PawPaceWidgetBundle: WidgetBundle {
    var body: some Widget {
        PawPaceCompactWidget()
        PawPaceHabitatWidget()
        PawPaceLiveActivityWidget()
    }
}

