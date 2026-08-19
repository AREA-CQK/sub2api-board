import SwiftUI
import WidgetKit

@main
struct Sub2APIBoardWidgetBundle: WidgetBundle {
    var body: some Widget {
        Sub2APIBoardWidget()
        LegacySub2APIBoardWidget()
    }
}
