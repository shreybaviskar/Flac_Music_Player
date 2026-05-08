//
//  DesignSystem.swift
//  AuraPlayer
//
//  Color palette, typography, and shared design tokens.
//

import SwiftUI

// MARK: - Color Palette

extension Color {
    /// Primary background — pure black for OLED true blacks.
    static let auraBackground = Color.black
    
    /// Elevated surface (cards, sheets, bottom bars).
    static let auraSurface = Color(white: 0.1)
    
    /// Secondary surface (grouped list backgrounds).
    static let auraSurfaceSecondary = Color(white: 0.07)
    
    /// Primary accent — vibrant pink (inspired by Apple Music).
    static let auraPrimary = Color.pink
    
    /// Secondary accent — rich purple for gradients.
    static let auraAccent = Color.purple
    
    /// Success / lossless indicator.
    static let auraSuccess = Color.green
    
    /// Warning / Hi-Res indicator.
    static let auraWarning = Color.orange
    
    /// Subtle divider / border.
    static let auraDivider = Color.white.opacity(0.08)
    
    /// Primary text.
    static let auraTextPrimary = Color.white
    
    /// Secondary text (subtitles, captions).
    static let auraTextSecondary = Color.white.opacity(0.6)
    
    /// Tertiary text (timestamps, metadata).
    static let auraTextTertiary = Color.white.opacity(0.4)
}

// MARK: - Typography

extension Font {
    /// Large title — 28pt bold rounded.
    static let auraTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    
    /// Headline — 20pt semibold rounded.
    static let auraHeadline = Font.system(size: 20, weight: .semibold, design: .rounded)
    
    /// Subheadline — 17pt medium.
    static let auraSubheadline = Font.system(size: 17, weight: .medium, design: .default)
    
    /// Body text — 16pt regular.
    static let auraBody = Font.system(size: 16, weight: .regular, design: .default)
    
    /// Caption — 12pt medium.
    static let auraCaption = Font.system(size: 12, weight: .medium, design: .default)
    
    /// Tiny — 10pt for quality badges.
    static let auraTiny = Font.system(size: 10, weight: .semibold, design: .rounded)
}

// MARK: - Quality Badge Colors

extension Track {
    /// Color for the quality badge based on codec and sample rate.
    var qualityColor: Color {
        if isHiRes {
            return .auraWarning
        } else if isLossless {
            return .auraSuccess
        } else {
            return .gray
        }
    }
    
    /// Short quality badge text (e.g. "Hi-Res", "Lossless", "MP3").
    var qualityBadge: String {
        if sampleRate >= 352800 {
            return "DSD"
        } else if isHiRes {
            return "Hi-Res"
        } else if isLossless {
            return "Lossless"
        } else {
            return codec.rawValue
        }
    }
}
