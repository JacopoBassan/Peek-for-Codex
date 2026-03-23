import AppKit
import Combine

@MainActor
final class NativePopoverViewController: NSViewController {
    private let model: UsageBarModel
    private var cancellables = Set<AnyCancellable>()
    private var relativeTimeTimer: Timer?
    private let contentStack = NSStackView()

    private let titleLabel = NSTextField(labelWithString: "Peek for Codex")
    private let subtitleLabel = NSTextField(labelWithString: "Waiting for first sync")
    private let windowsStack = NSStackView()
    private let errorLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let openButton = NSButton(title: "Open Codex", target: nil, action: nil)
    private let footerDivider = NSView()
    private let creditsDivider = NSView()
    private let creditsStack = NSStackView()

    init(model: UsageBarModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let backgroundView = NSVisualEffectView()
        backgroundView.material = .popover
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        view = backgroundView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        bindModel()
        startRelativeTimeTimer()
        updateUI()
    }

    private func configureUI() {
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.maximumNumberOfLines = 1

        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail

        errorLabel.font = .preferredFont(forTextStyle: .caption1)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 0
        errorLabel.isHidden = true

        windowsStack.orientation = .vertical
        windowsStack.alignment = .leading
        windowsStack.spacing = 0

        refreshButton.bezelStyle = .recessed
        refreshButton.controlSize = .small
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)

        openButton.bezelStyle = .recessed
        openButton.controlSize = .small
        openButton.target = self
        openButton.action = #selector(openTapped)

        let buttonRow = NSStackView(views: [refreshButton, openButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = UIStyle.Popover.buttonSpacing
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let trailingSpacer = spacer()
        buttonRow.insertArrangedSubview(trailingSpacer, at: 1)
        trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailingSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        footerDivider.wantsLayer = true
        footerDivider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        footerDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        creditsDivider.wantsLayer = true
        creditsDivider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        creditsDivider.translatesAutoresizingMaskIntoConstraints = false
        creditsDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        creditsDivider.isHidden = true

        creditsStack.orientation = .vertical
        creditsStack.alignment = .leading
        creditsStack.spacing = 0
        creditsStack.translatesAutoresizingMaskIntoConstraints = false
        creditsStack.isHidden = true

        let headerStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = UIStyle.Popover.titleToSubtitleSpacing
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        for view in [
            headerStack,
            windowsStack,
            creditsDivider,
            creditsStack,
            errorLabel,
            footerDivider,
            buttonRow,
        ] {
            contentStack.addArrangedSubview(view)
        }

        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UIStyle.Popover.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UIStyle.Popover.contentInset),
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: UIStyle.Popover.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -UIStyle.Popover.contentInset),
            view.widthAnchor.constraint(equalToConstant: UIStyle.Popover.width),
            headerStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            titleLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
            windowsStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            creditsDivider.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            creditsStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            footerDivider.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])

        contentStack.setCustomSpacing(UIStyle.Popover.subtitleToWindowsSpacing, after: headerStack)
        contentStack.setCustomSpacing(UIStyle.Popover.windowsToFooterSpacing, after: windowsStack)
        contentStack.setCustomSpacing(UIStyle.Popover.rowToDividerSpacing, after: creditsDivider)
        contentStack.setCustomSpacing(UIStyle.Popover.windowsToFooterSpacing, after: creditsStack)
        contentStack.setCustomSpacing(UIStyle.Popover.windowsToFooterSpacing, after: errorLabel)
        contentStack.setCustomSpacing(UIStyle.Popover.footerToButtonsSpacing, after: footerDivider)
    }

    private func bindModel() {
        Publishers.CombineLatest(
            Publishers.CombineLatest4(model.$snapshot, model.$nextRefreshAt, model.$errorMessage, model.$isRefreshing),
            model.$showsCreditsInPopup
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updateUI()
            }
            .store(in: &cancellables)
    }

    private func startRelativeTimeTimer() {
        relativeTimeTimer = Timer.scheduledTimer(withTimeInterval: UIStyle.Refresh.subtitleTimerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSubtitle()
            }
        }
        RunLoop.main.add(relativeTimeTimer!, forMode: .common)
    }

    private func updateUI() {
        updateSubtitle()

        refreshButton.title = model.isRefreshing ? "Refreshing..." : "Refresh"
        refreshButton.isEnabled = !model.isRefreshing

        if let error = model.errorMessage, !error.isEmpty {
            errorLabel.isHidden = false
            errorLabel.stringValue = error
        } else {
            errorLabel.isHidden = true
            errorLabel.stringValue = ""
        }

        rebuildCredits()
        rebuildWindows()
        updatePreferredContentSize()
    }

    private func updateSubtitle() {
        subtitleLabel.stringValue = UsageFormatting.refreshSubtitle(
            isRefreshing: model.isRefreshing,
            nextRefreshAt: model.nextRefreshAt
        )
    }

    private func rebuildWindows() {
        windowsStack.arrangedSubviews.forEach { subview in
            windowsStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let windows = model.displayWindows

        if windows.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No Codex rate-limit windows available yet.")
            emptyLabel.font = .preferredFont(forTextStyle: .body)
            emptyLabel.textColor = .secondaryLabelColor
            windowsStack.addArrangedSubview(emptyLabel)
            return
        }

        for (index, window) in windows.enumerated() {
            let row = makeWindowRow(window)
            windowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: windowsStack.widthAnchor).isActive = true

            if index < windows.count - 1 {
                let divider = separator()
                windowsStack.addArrangedSubview(divider)
                windowsStack.setCustomSpacing(UIStyle.Popover.rowToDividerSpacing, after: row)
                windowsStack.setCustomSpacing(UIStyle.Popover.rowToDividerSpacing, after: divider)
            }
        }
    }

    private func rebuildCredits() {
        creditsStack.arrangedSubviews.forEach { subview in
            creditsStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let planType = model.snapshot?.planType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let showsPlan = !planType.isEmpty

        guard model.showsCreditsInPopup || showsPlan else {
            creditsDivider.isHidden = true
            creditsStack.isHidden = true
            return
        }

        if model.showsCreditsInPopup {
            let title = NSTextField(labelWithString: "Credits")
            title.font = .preferredFont(forTextStyle: .headline)

            let value = NSTextField(labelWithString: model.snapshot?.credits?.popupDisplayValue ?? "0")
            value.font = .preferredFont(forTextStyle: .body)

            let header = NSStackView(views: [title, spacer(), value])
            header.orientation = .horizontal
            header.alignment = .firstBaseline
            header.spacing = UIStyle.Popover.headerSpacing
            header.translatesAutoresizingMaskIntoConstraints = false

            creditsStack.addArrangedSubview(header)
            header.widthAnchor.constraint(equalTo: creditsStack.widthAnchor).isActive = true
        }

        if showsPlan {
            let plan = NSTextField(labelWithString: "Plan: \(planType)")
            plan.font = .preferredFont(forTextStyle: .caption1)
            plan.textColor = .secondaryLabelColor
            plan.maximumNumberOfLines = 0
            creditsStack.addArrangedSubview(plan)
            plan.widthAnchor.constraint(equalTo: creditsStack.widthAnchor).isActive = true

            if model.showsCreditsInPopup, let header = creditsStack.arrangedSubviews.first {
                creditsStack.setCustomSpacing(UIStyle.Popover.barToResetSpacing, after: header)
            }
        }

        creditsDivider.isHidden = false
        creditsStack.isHidden = false
    }

    private func makeWindowRow(_ window: DisplayWindow) -> NSView {
        let title = NSTextField(labelWithString: window.popupLabel)
        title.font = .preferredFont(forTextStyle: .headline)

        let value = NSTextField(labelWithString: UsageFormatting.popupValue(for: window))
        value.font = .preferredFont(forTextStyle: .body)

        let header = NSStackView(views: [title, spacer(), value])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = UIStyle.Popover.headerSpacing
        header.translatesAutoresizingMaskIntoConstraints = false

        let progress = NativeWhiteProgressBar(value: max(0, min(1, 1.0 - (window.usedPercent / 100.0))))
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.heightAnchor.constraint(equalToConstant: UIStyle.Popover.progressHeight).isActive = true

        let reset = NSTextField(labelWithString: UsageFormatting.popupResetString(for: window))
        reset.font = .preferredFont(forTextStyle: .caption1)
        reset.textColor = .secondaryLabelColor
        reset.maximumNumberOfLines = 0

        let stack = NSStackView(views: [header, progress, reset])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        progress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        reset.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(UIStyle.Popover.headerToBarSpacing, after: header)
        stack.setCustomSpacing(UIStyle.Popover.barToResetSpacing, after: progress)
        return stack
    }

    private func separator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.separatorColor.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func updatePreferredContentSize() {
        view.layoutSubtreeIfNeeded()
        let fittingHeight = contentStack.fittingSize.height + (UIStyle.Popover.contentInset * 2)
        preferredContentSize = NSSize(width: UIStyle.Popover.width, height: fittingHeight)
    }

    @objc
    private func refreshTapped() {
        Task {
            await model.refresh()
        }
    }

    @objc
    private func openTapped() {
        model.openCodex()
    }
}

private final class NativeWhiteProgressBar: NSView {
    var value: Double {
        didSet {
            needsDisplay = true
        }
    }

    init(value: Double) {
        self.value = value
        super.init(frame: .zero)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: UIStyle.Popover.progressIntrinsicWidth, height: UIStyle.Popover.progressHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = bounds.insetBy(dx: 0, dy: 1)
        let radius = trackRect.height / 2
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(UIStyle.Popover.progressTrackAlpha).setFill()
        trackPath.fill()

        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(0, min(trackRect.width, trackRect.width * value)),
            height: trackRect.height
        )
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        NSColor.white.setFill()
        fillPath.fill()
    }
}
