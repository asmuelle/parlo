#if canImport(SwiftUI)
    import SwiftUI

    public extension ColorToken {
        var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
        }
    }

    /// Typography: New York (serif) carries the travel-journal voice on
    /// titles and recaps; SF Rounded keeps conversation low-stakes.
    public enum ParloTypography {
        public static var scenarioTitle: Font {
            .system(.title2, design: .serif).weight(.semibold)
        }

        public static var journalHeading: Font {
            .system(.largeTitle, design: .serif).weight(.bold)
        }

        public static var bubble: Font {
            .system(.body, design: .rounded)
        }

        public static var chip: Font {
            .system(.footnote, design: .rounded).weight(.medium)
        }

        public static var caption: Font {
            .system(.caption, design: .rounded)
        }
    }
#endif
