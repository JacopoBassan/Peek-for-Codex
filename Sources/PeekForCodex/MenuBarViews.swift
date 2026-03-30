import SwiftUI

struct StatusMetersView: View {
    @ObservedObject var model: UsageBarModel

    private var usageWindow: DisplayWindow {
        model.displayWindows.first(where: \.isFiveHourWindow)
        ?? DisplayWindow(id: "5h-placeholder", label: "5h", usedPercent: 0, remainingPercent: 0, resetDate: nil, durationMinutes: 300)
    }

    private var weeklyWindow: DisplayWindow {
        model.displayWindows.first(where: \.isWeeklyWindow)
        ?? DisplayWindow(id: "w-placeholder", label: "W", usedPercent: 0, remainingPercent: 0, resetDate: nil, durationMinutes: 10_080)
    }

    var body: some View {
        HStack(spacing: UIStyle.MenuBar.horizontalSpacing) {
            IconColumnView(isDimmed: model.snapshot == nil)

            VStack(alignment: .leading, spacing: UIStyle.MenuBar.rowSpacing) {
                StatusLineView(
                    label: usageWindow.menuBarLabel,
                    value: UsageFormatting.menuBarValue(for: usageWindow),
                    isDimmed: model.snapshot == nil
                )
                .padding(.bottom, UIStyle.MenuBar.rowBottomPadding)

                StatusLineView(
                    label: weeklyWindow.menuBarLabel,
                    value: UsageFormatting.menuBarValue(for: weeklyWindow),
                    isDimmed: model.snapshot == nil
                )
                .padding(.top, UIStyle.MenuBar.rowTopPadding)
            }
        }
        .padding(.top, UIStyle.MenuBar.topPadding)
        .frame(height: UIStyle.MenuBar.height, alignment: .leading)
        .fixedSize()
        .background(Color.clear)
    }
}

private struct IconColumnView: View {
    let isDimmed: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Text(">")
                .font(.system(size: UIStyle.MenuBar.iconGlyphSize, weight: .regular, design: .monospaced))
                .foregroundStyle(foregroundColor)
                .frame(width: UIStyle.MenuBar.iconWidth, height: UIStyle.MenuBar.iconHeight, alignment: .leading)

            Text("_")
                .font(.system(size: UIStyle.MenuBar.iconGlyphSize, weight: .regular, design: .monospaced))
                .foregroundStyle(foregroundColor)
                .frame(width: UIStyle.MenuBar.iconWidth, height: UIStyle.MenuBar.iconHeight, alignment: .leading)
                .offset(y: UIStyle.MenuBar.iconYOffset)
        }
        .frame(width: UIStyle.MenuBar.iconWidth, height: UIStyle.MenuBar.iconContainerHeight)
    }

    private var foregroundColor: Color {
        let base = colorScheme == .dark ? Color.white : Color(nsColor: .labelColor)
        return base.opacity(isDimmed ? 0.45 : 1)
    }
}

private struct StatusLineView: View {
    let label: String
    let value: String
    let isDimmed: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: UIStyle.MenuBar.lineSpacing) {
            Text(label)
                .font(.system(size: UIStyle.MenuBar.fontSize, weight: .regular, design: .default))
                .foregroundStyle(foregroundColor)
                .frame(width: UIStyle.MenuBar.labelWidth, alignment: .leading)

            Text(value)
                .font(.system(size: UIStyle.MenuBar.fontSize, weight: .regular, design: .default))
                .foregroundStyle(foregroundColor)
                .monospacedDigit()
                .frame(width: UIStyle.MenuBar.valueWidth, alignment: .trailing)
        }
        .frame(height: UIStyle.MenuBar.rowHeight, alignment: .leading)
    }

    private var foregroundColor: Color {
        let base = colorScheme == .dark ? Color.white : Color(nsColor: .labelColor)
        return base.opacity(isDimmed ? 0.45 : 1)
    }
}
