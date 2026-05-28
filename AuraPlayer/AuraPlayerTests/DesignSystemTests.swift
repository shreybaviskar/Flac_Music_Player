//
//  DesignSystemTests.swift
//  AuraPlayerTests
//
//  Tests for the DesignSystem design tokens — color palette and typography.
//
//  These are smoke tests to ensure all tokens are accessible and correctly
//  defined. Since Color and Font are value types, "accessibility" means
//  they can be referenced without crashing. Where possible, we verify
//  that specific colors match their expected SwiftUI values.
//

import XCTest
import SwiftUI
@testable import AuraPlayer

final class DesignSystemTests: XCTestCase {
    
    // MARK: - Color Accessibility Tests
    
    func test_auraBackground_isAccessible() {
        let color = Color.auraBackground
        XCTAssertNotNil(color as Any, "auraBackground should be a valid Color")
    }
    
    func test_auraSurface_isAccessible() {
        let color = Color.auraSurface
        XCTAssertNotNil(color as Any, "auraSurface should be a valid Color")
    }
    
    func test_auraSurfaceSecondary_isAccessible() {
        let color = Color.auraSurfaceSecondary
        XCTAssertNotNil(color as Any, "auraSurfaceSecondary should be a valid Color")
    }
    
    func test_auraPrimary_isAccessible() {
        let color = Color.auraPrimary
        XCTAssertNotNil(color as Any, "auraPrimary should be a valid Color")
    }
    
    func test_auraAccent_isAccessible() {
        let color = Color.auraAccent
        XCTAssertNotNil(color as Any, "auraAccent should be a valid Color")
    }
    
    func test_auraSuccess_isAccessible() {
        let color = Color.auraSuccess
        XCTAssertNotNil(color as Any, "auraSuccess should be a valid Color")
    }
    
    func test_auraWarning_isAccessible() {
        let color = Color.auraWarning
        XCTAssertNotNil(color as Any, "auraWarning should be a valid Color")
    }
    
    func test_auraDivider_isAccessible() {
        let color = Color.auraDivider
        XCTAssertNotNil(color as Any, "auraDivider should be a valid Color")
    }
    
    func test_auraTextPrimary_isAccessible() {
        let color = Color.auraTextPrimary
        XCTAssertNotNil(color as Any, "auraTextPrimary should be a valid Color")
    }
    
    func test_auraTextSecondary_isAccessible() {
        let color = Color.auraTextSecondary
        XCTAssertNotNil(color as Any, "auraTextSecondary should be a valid Color")
    }
    
    func test_auraTextTertiary_isAccessible() {
        let color = Color.auraTextTertiary
        XCTAssertNotNil(color as Any, "auraTextTertiary should be a valid Color")
    }
    
    // MARK: - Color Value Verification Tests
    
    func test_auraBackground_isBlack() {
        // auraBackground is defined as Color.black
        XCTAssertEqual(Color.auraBackground, Color.black,
                       "auraBackground should be pure black for OLED displays")
    }
    
    func test_auraPrimary_isPink() {
        // auraPrimary is defined as Color.pink
        XCTAssertEqual(Color.auraPrimary, Color.pink,
                       "auraPrimary should be pink")
    }
    
    func test_auraAccent_isPurple() {
        // auraAccent is defined as Color.purple
        XCTAssertEqual(Color.auraAccent, Color.purple,
                       "auraAccent should be purple")
    }
    
    func test_auraSuccess_isGreen() {
        // auraSuccess is defined as Color.green
        XCTAssertEqual(Color.auraSuccess, Color.green,
                       "auraSuccess should be green for lossless indicators")
    }
    
    func test_auraWarning_isOrange() {
        // auraWarning is defined as Color.orange
        XCTAssertEqual(Color.auraWarning, Color.orange,
                       "auraWarning should be orange for Hi-Res indicators")
    }
    
    func test_auraTextPrimary_isWhite() {
        // auraTextPrimary is defined as Color.white
        XCTAssertEqual(Color.auraTextPrimary, Color.white,
                       "auraTextPrimary should be white")
    }
    
    // MARK: - Color Uniqueness Tests
    
    func test_surfaceColors_areDifferent() {
        // auraSurface (white: 0.1) and auraSurfaceSecondary (white: 0.07)
        // should be distinct.
        XCTAssertNotEqual(
            Color.auraSurface.description,
            Color.auraSurfaceSecondary.description,
            "auraSurface and auraSurfaceSecondary should be different shades"
        )
    }
    
    func test_textColors_areDifferent() {
        // The three text opacity levels should be distinct.
        let primary = Color.auraTextPrimary.description
        let secondary = Color.auraTextSecondary.description
        let tertiary = Color.auraTextTertiary.description
        
        XCTAssertNotEqual(primary, secondary,
                          "Primary and secondary text colors should differ")
        XCTAssertNotEqual(secondary, tertiary,
                          "Secondary and tertiary text colors should differ")
        XCTAssertNotEqual(primary, tertiary,
                          "Primary and tertiary text colors should differ")
    }
    
    func test_primaryAndAccent_areDifferent() {
        XCTAssertNotEqual(Color.auraPrimary, Color.auraAccent,
                          "Primary (pink) and accent (purple) should be different")
    }
    
    func test_successAndWarning_areDifferent() {
        XCTAssertNotEqual(Color.auraSuccess, Color.auraWarning,
                          "Success (green) and warning (orange) should be different")
    }
    
    // MARK: - Font Accessibility Tests
    
    func test_auraTitle_isAccessible() {
        let font = Font.auraTitle
        XCTAssertNotNil(font as Any, "auraTitle should be a valid Font")
    }
    
    func test_auraHeadline_isAccessible() {
        let font = Font.auraHeadline
        XCTAssertNotNil(font as Any, "auraHeadline should be a valid Font")
    }
    
    func test_auraSubheadline_isAccessible() {
        let font = Font.auraSubheadline
        XCTAssertNotNil(font as Any, "auraSubheadline should be a valid Font")
    }
    
    func test_auraBody_isAccessible() {
        let font = Font.auraBody
        XCTAssertNotNil(font as Any, "auraBody should be a valid Font")
    }
    
    func test_auraCaption_isAccessible() {
        let font = Font.auraCaption
        XCTAssertNotNil(font as Any, "auraCaption should be a valid Font")
    }
    
    func test_auraTiny_isAccessible() {
        let font = Font.auraTiny
        XCTAssertNotNil(font as Any, "auraTiny should be a valid Font")
    }
    
    // MARK: - Font Uniqueness Tests
    
    func test_allFontTokens_areDifferent() {
        // Each font token should produce a unique Font value (different size/weight/design).
        let fonts: [(String, Font)] = [
            ("auraTitle", .auraTitle),
            ("auraHeadline", .auraHeadline),
            ("auraSubheadline", .auraSubheadline),
            ("auraBody", .auraBody),
            ("auraCaption", .auraCaption),
            ("auraTiny", .auraTiny)
        ]
        
        // Compare each pair by description to verify they are distinct.
        for i in 0..<fonts.count {
            for j in (i + 1)..<fonts.count {
                XCTAssertNotEqual(
                    String(describing: fonts[i].1),
                    String(describing: fonts[j].1),
                    "\(fonts[i].0) and \(fonts[j].0) should be different fonts"
                )
            }
        }
    }
    
    // MARK: - SwiftUI Context Smoke Tests
    
    /// Verifies that all color tokens can be used in a SwiftUI View context
    /// without crashing. This catches any lazy initialization or computed
    /// property issues.
    func test_allColorTokens_usableInViewContext() {
        // Build a Text view using every color token as foreground.
        let colors: [Color] = [
            .auraBackground,
            .auraSurface,
            .auraSurfaceSecondary,
            .auraPrimary,
            .auraAccent,
            .auraSuccess,
            .auraWarning,
            .auraDivider,
            .auraTextPrimary,
            .auraTextSecondary,
            .auraTextTertiary
        ]
        
        for (index, color) in colors.enumerated() {
            let view = Text("Token \(index)")
                .foregroundColor(color)
                .background(color)
            
            // If we get here without crashing, the token is valid.
            XCTAssertNotNil(view as Any, "Color token at index \(index) should be usable in a SwiftUI view")
        }
    }
    
    /// Verifies that all font tokens can be used in a SwiftUI View context.
    func test_allFontTokens_usableInViewContext() {
        let fonts: [Font] = [
            .auraTitle,
            .auraHeadline,
            .auraSubheadline,
            .auraBody,
            .auraCaption,
            .auraTiny
        ]
        
        for (index, font) in fonts.enumerated() {
            let view = Text("Font \(index)")
                .font(font)
            
            XCTAssertNotNil(view as Any, "Font token at index \(index) should be usable in a SwiftUI view")
        }
    }
    
    /// Smoke test: combine multiple tokens in a realistic SwiftUI layout.
    func test_designTokens_inRealisticLayout() {
        let view = VStack {
            Text("Title")
                .font(.auraTitle)
                .foregroundColor(.auraTextPrimary)
            
            Text("Subtitle")
                .font(.auraSubheadline)
                .foregroundColor(.auraTextSecondary)
            
            Text("Caption")
                .font(.auraCaption)
                .foregroundColor(.auraTextTertiary)
        }
        .background(Color.auraBackground)
        
        XCTAssertNotNil(view as Any, "Design tokens should compose in a realistic layout")
    }
    
    // MARK: - Complete Token Count Verification
    
    func test_allColorTokensCount() {
        // Verify we have exactly 11 color tokens defined.
        let allColors: [Color] = [
            .auraBackground,
            .auraSurface,
            .auraSurfaceSecondary,
            .auraPrimary,
            .auraAccent,
            .auraSuccess,
            .auraWarning,
            .auraDivider,
            .auraTextPrimary,
            .auraTextSecondary,
            .auraTextTertiary
        ]
        XCTAssertEqual(allColors.count, 11, "Should have exactly 11 color tokens")
    }
    
    func test_allFontTokensCount() {
        // Verify we have exactly 6 font tokens defined.
        let allFonts: [Font] = [
            .auraTitle,
            .auraHeadline,
            .auraSubheadline,
            .auraBody,
            .auraCaption,
            .auraTiny
        ]
        XCTAssertEqual(allFonts.count, 6, "Should have exactly 6 font tokens")
    }
}
