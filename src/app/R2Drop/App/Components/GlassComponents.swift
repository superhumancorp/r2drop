// R2Drop/App/Components/GlassComponents.swift
// Reusable liquid glass UI components shared across all Settings tabs.
// Provides consistent frosted-glass card containers and section headers
// matching the Tailscale-inspired design language.

import SwiftUI

// MARK: - GlassCard

/// A frosted-glass card container. Wraps content in a rounded rectangle
/// with `.ultraThinMaterial` background and subtle border.
/// Usage: `GlassCard { Text("Hello") }`
struct GlassCard<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - GlassSectionHeader

/// A section header with consistent styling. Bold title + optional subtitle.
struct GlassSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - GlassToggleRow

/// A toggle row that matches the Tailscale style — label on left, toggle on right.
struct GlassToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

// MARK: - GlassInfoRow

/// A key-value display row. Label on left, value on right.
struct GlassInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .secondary
    var monospaced: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .foregroundColor(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - GlassEmptyState

/// Consistent empty state card with icon, title, and subtitle.
struct GlassEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - GlassBackground

/// Full-window liquid glass background layer. Use as a ZStack base.
struct GlassBackground: View {
    var body: some View {
        ZStack {
            // Window tint layer
            Color(nsColor: .windowBackgroundColor)
            // Frosted glass overlay
            Rectangle()
                .fill(.thinMaterial)
        }
    }
}

// MARK: - GlassSearchBar

/// Frosted-glass search field matching the Tailscale search bar style.
struct GlassSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var onClear: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
            if !text.isEmpty {
                Button(action: {
                    text = ""
                    onClear?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - StatusPill

/// A small colored pill for status badges (e.g., "Uploading", "Paused").
struct StatusPill: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
