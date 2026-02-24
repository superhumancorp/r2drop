// R2Drop/App/Onboarding/ConfettiView.swift
// Lightweight confetti animation for celebration moments.
// Spawns colored emoji particles that fall with random trajectories.
// Respects macOS "Reduce Motion" accessibility setting.

import SwiftUI

/// A single confetti particle with position, color, and animation state.
private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let emoji: String
    let startX: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let horizontalDrift: CGFloat
    let rotation: Double
    let delay: Double
    let duration: Double
}

/// Displays animated confetti particles when `isActive` becomes true.
/// Usage: `ConfettiView(isActive: $showConfetti)`
struct ConfettiView: View {
    @Binding var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [ConfettiPiece] = []
    @State private var animating = false

    /// Emoji options for confetti particles.
    private let emojis = ["🎉", "🎊", "✨", "⭐️", "💙", "🩵", "💎"]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    Text(piece.emoji)
                        .font(.title2)
                        .offset(
                            x: animating ? piece.startX + piece.horizontalDrift : piece.startX,
                            y: animating ? piece.endY : piece.startY
                        )
                        .rotationEffect(.degrees(animating ? piece.rotation : 0))
                        .opacity(animating ? 0 : 1)
                        .animation(
                            reduceMotion ? .none :
                                .easeIn(duration: piece.duration)
                                .delay(piece.delay),
                            value: animating
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: isActive) { active in
                if active {
                    spawnPieces(in: geo.size)
                }
            }
        }
        .allowsHitTesting(false) // Don't block interaction
    }

    /// Create random confetti particles spread across the view.
    private func spawnPieces(in size: CGSize) {
        guard !reduceMotion else { return }

        let count = 30
        pieces = (0..<count).map { _ in
            ConfettiPiece(
                emoji: emojis.randomElement()!,
                startX: CGFloat.random(in: -size.width / 2 ... size.width / 2),
                startY: CGFloat.random(in: -size.height * 0.6 ... -size.height * 0.2),
                endY: size.height * 0.6,
                horizontalDrift: CGFloat.random(in: -60...60),
                rotation: Double.random(in: -360...360),
                delay: Double.random(in: 0...0.5),
                duration: Double.random(in: 1.2...2.0)
            )
        }

        // Trigger the animation
        withAnimation { animating = true }

        // Clean up after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            pieces = []
            animating = false
        }
    }
}
