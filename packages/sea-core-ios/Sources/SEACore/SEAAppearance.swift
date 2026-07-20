import UIKit

/// SDK-controlled appearance (contract §3.2, spec §18.1).
///
/// Colors and text only. There is no layout injection here, and nothing in
/// this type is ever used to touch, restyle, or overlay web content (§13).
public struct SEAAppearance {
    public var headerBackground: UIColor
    public var headerText: UIColor
    public var accent: UIColor
    public var closeIconTint: UIColor
    public var cornerRadius: CGFloat
    /// `nil` means the header falls back to the live page title (contract §9).
    public var title: String?
    public var showsGrabber: Bool

    public init(
        headerBackground: UIColor,
        headerText: UIColor,
        accent: UIColor,
        closeIconTint: UIColor,
        cornerRadius: CGFloat,
        title: String? = nil,
        showsGrabber: Bool = true
    ) {
        self.headerBackground = headerBackground
        self.headerText = headerText
        self.accent = accent
        self.closeIconTint = closeIconTint
        self.cornerRadius = cornerRadius
        self.title = title
        self.showsGrabber = showsGrabber
    }

    public static let `default` = SEAAppearance(
        headerBackground: .systemBackground,
        headerText: .label,
        accent: .systemBlue,
        closeIconTint: .secondaryLabel,
        cornerRadius: 16,
        title: nil,
        showsGrabber: true
    )
}
