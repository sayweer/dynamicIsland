import SwiftUI

/// Content flanking the physical notch while collapsed:
/// clock / running timer on the left, music or battery on the right.
struct CollapsedView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var music: MusicManager
    @EnvironmentObject private var timers: TimerCenter
    @EnvironmentObject private var stats: SystemStats

    var body: some View {
        HStack(spacing: 0) {
            leftZone
                .frame(width: 74)
            Spacer(minLength: 8)
            rightZone
                .frame(width: 74)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var leftZone: some View {
        if let badge = timers.collapsedBadge {
            Text(badge)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private var rightZone: some View {
        if let playing = music.nowPlaying, playing.isPlaying {
            HStack(spacing: 5) {
                if let artwork = music.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 17, height: 17)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                EqualizerBars(playing: true)
            }
        } else if let level = stats.batteryLevel {
            HStack(spacing: 3) {
                if stats.batteryCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                }
                Text("%\(level)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: batterySymbol(level))
                    .font(.system(size: 11))
                    .foregroundStyle(level <= 20 ? .red : .white.opacity(0.85))
            }
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

/// Tiny animated bars synced to playback state.
struct EqualizerBars: View {
    var playing: Bool
    @State private var heights: [CGFloat] = [7, 12, 9]

    private let timer = Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.green)
                    .frame(width: 2.5, height: heights[index])
            }
        }
        .frame(height: 14, alignment: .bottom)
        .onReceive(timer) { _ in
            guard playing else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                heights = heights.map { _ in CGFloat.random(in: 4...14) }
            }
        }
    }
}
