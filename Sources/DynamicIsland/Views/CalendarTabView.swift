import SwiftUI
import EventKit

/// Today's schedule and open reminders.
struct CalendarTabView: View {
    @EnvironmentObject private var calendar: CalendarManager

    var body: some View {
        Group {
            switch (calendar.eventAccess, calendar.reminderAccess) {
            case (.denied, .denied):
                deniedView
            case (.unknown, _), (_, .unknown):
                requestView
            default:
                contentView
            }
        }
        .islandCard()
        .onAppear {
            if calendar.eventAccess == .granted || calendar.reminderAccess == .granted {
                calendar.refresh()
            }
        }
    }

    private var requestView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.3))
            Text("Takvim ve anımsatıcılarınızı çentikte görün")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Button("Erişime İzin Ver") {
                calendar.requestAccessAndRefresh()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var deniedView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.3))
            Text("Takvim erişimi reddedildi")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
            Text("Gizlilik ve Güvenlik → Takvimler bölümünden izin verebilirsiniz")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
            Button("Sistem Ayarları'nı Aç") {
                SystemSettingsPane.calendars.open()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var contentView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                CardTitle("Etkinlikler", symbol: "calendar", tint: .red)
                if calendar.upcomingEvents.isEmpty {
                    Text("Önümüzdeki 7 günde etkinlik yok")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(calendar.upcomingEvents, id: \.eventIdentifier) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 6) {
                CardTitle("Anımsatıcılar", symbol: "checklist", tint: .orange)
                if calendar.reminderAccess != .granted {
                    Text("Anımsatıcı erişimi verilmedi")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else if calendar.openReminders.isEmpty {
                    Text("Bekleyen anımsatıcı yok 🎉")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(calendar.openReminders, id: \.calendarItemIdentifier) { reminder in
                                reminderRow(reminder)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                calendar.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Yenile")
        }
    }

    private func eventRow(_ event: EKEvent) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(eventColor(event))
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Etkinlik")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                if event.isAllDay {
                    Text("Tüm gün")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    let day = event.startDate.formatted(.dateTime.day().month())
                    let start = event.startDate.formatted(.dateTime.hour().minute())
                    let end = event.endDate.formatted(.dateTime.hour().minute())
                    Text("\(day) · \(start)–\(end)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// `EKEvent.calendar` silinmiş takvimlerde nil dönebilir (IUO) — güvenli okuma.
    private func eventColor(_ event: EKEvent) -> Color {
        if let calendar = event.calendar as EKCalendar?, let cgColor = calendar.cgColor {
            return Color(cgColor: cgColor)
        }
        return .red
    }

    private func reminderRow(_ reminder: EKReminder) -> some View {
        HStack(spacing: 7) {
            Button {
                calendar.complete(reminder)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Tamamlandı olarak işaretle")
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title ?? "Anımsatıcı")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                if let due = reminder.dueDateComponents?.date {
                    Text(due, format: .dateTime.day().month().hour().minute())
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
        }
    }
}
