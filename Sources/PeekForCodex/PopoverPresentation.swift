import Foundation

struct PopoverPresentation {
    let windowSections: [PopoverWindowPresentation]
    let creditsSection: PopoverCreditsPresentation?
    let errorMessage: String?
    let emptyStateMessage: String?
}

struct PopoverWindowPresentation: Identifiable {
    let id: String
    let title: String
    let valueText: String
    let progressValue: Double
    let resetText: String
}

struct PopoverCreditsPresentation {
    let title: String?
    let valueText: String?
    let planText: String?
}
