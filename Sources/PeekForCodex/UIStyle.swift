import SwiftUI

enum UIStyle {
    enum MenuBar {
        static let iconGlyphSize: CGFloat = 9.5
        static let iconWidth: CGFloat = 7
        static let iconHeight: CGFloat = 7
        static let iconYOffset: CGFloat = -3
        static let iconContainerHeight: CGFloat = 14
        static let horizontalSpacing: CGFloat = 3
        static let rowSpacing: CGFloat = 0
        static let topPadding: CGFloat = 1
        static let rowBottomPadding: CGFloat = 3
        static let rowTopPadding: CGFloat = 1
        static let height: CGFloat = 23
        static let lineSpacing: CGFloat = 1
        static let labelWidth: CGFloat = 20
        static let valueWidth: CGFloat = 30
        static let rowHeight: CGFloat = 10
        static let fontSize: CGFloat = 10
    }

    enum Popover {
        static let width: CGFloat = 278
        static let contentInset: CGFloat = 12
        static let titleToSubtitleSpacing: CGFloat = 4
        static let subtitleToWindowsSpacing: CGFloat = 12
        static let windowsToFooterSpacing: CGFloat = 8
        static let footerToButtonsSpacing: CGFloat = 10
        static let rowToDividerSpacing: CGFloat = 10
        static let headerToBarSpacing: CGFloat = 7
        static let barToResetSpacing: CGFloat = 8
        static let headerSpacing: CGFloat = 3
        static let buttonSpacing: CGFloat = 8
        static let progressHeight: CGFloat = 8
        static let progressIntrinsicWidth: CGFloat = 200
        static let progressTrackAlpha: CGFloat = 0.28
    }

    enum Refresh {
        static let subtitleTimerInterval: TimeInterval = 1
    }
}
