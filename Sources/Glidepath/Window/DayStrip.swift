import SwiftUI

extension ScheduleTime {
    /// "7:00 AM", the chip and pin label.
    var clock: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12):\(String(format: "%02d", minute)) \(hour < 12 ? "AM" : "PM")"
    }
}

/// The pin being dragged. The strip keeps it, so the pin follows the pointer until the drag ends.
@MainActor
final class DayStripDrag: ObservableObject {
    @Published var dragging: ScheduleTime?
    @Published var offset: CGFloat = 0
}

/// The 24 h day strip (base.css day track): night bands, an amber pin per sweep time, a blue now line and hour ticks.
/// It holds no config. A click on the track reports a minute of the day, and a dragged pin reports its new minute when
/// the drag ends; the owner saves the change. Used by Schedule and by the onboarding schedule step.
struct DayStrip: View {
    let times: [ScheduleTime]
    /// A click that is not on a pin: the minute of the day, 0 to 1439.
    let onAdd: (Int) -> Void
    /// A pin dragged to a new minute of the day.
    let onMove: (ScheduleTime, Int) -> Void

    @StateObject private var drag = DayStripDrag()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                track(width: geo.size.width)
            }
            .frame(height: 72)
            ticks
                .frame(height: 16)
                .padding(.top, WinMetrics.s8)
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(WinTheme.surface))
    }

    /// The hour ticks: the first starts at its position, the last ends at it, the rest are centred on it.
    private var ticks: some View {
        let labels: [(text: String, fraction: CGFloat)] = [("12 AM", 0), ("6 AM", 0.25), ("12 PM", 0.5), ("6 PM", 0.75), ("12 AM", 1)]
        return GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, tick in
                    Text(tick.text)
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.faint)
                        .monospacedDigit()
                        .fixedSize()
                        .alignmentGuide(.leading) { d in
                            let shift = tick.fraction == 0 ? 0 : (tick.fraction == 1 ? d.width : d.width / 2)
                            return shift - tick.fraction * width
                        }
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    /// Track geometry, from the mockup: rail at y 52, night bands and the now line at y 40 (26 tall), pins from y 22
    /// with a 12 pt dot centred on the rail.
    private func track(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(WinTheme.control).frame(width: width, height: 2).offset(y: 51)
            Rectangle().fill(WinTheme.night)
                .frame(width: width * 0.25, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .offset(y: 40)
            Rectangle().fill(WinTheme.night)
                .frame(width: width * (1 - 22.0 / 24), height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .offset(x: width * 22.0 / 24, y: 40)
            Rectangle().fill(WinTheme.blue)
                .frame(width: 2, height: 26)
                .offset(x: fraction(of: Date()) * width - 1, y: 40)
            ForEach(times, id: \.self) { time in
                pin(time, width: width)
            }
        }
        .frame(width: width, height: 72, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                // A tap on a pin is not a new time.
                let nearPin = times.contains { abs(xPosition($0, width: width) - value.location.x) < 14 }
                guard !nearPin else { return }
                onAdd(minuteOfDay(atX: value.location.x, width: width))
            }
        )
    }

    /// One sweep pin: a label above, the 2 pt amber pin and the dot on the rail. Dragging it moves the time; the new
    /// time is reported when the drag ends.
    private func pin(_ time: ScheduleTime, width: CGFloat) -> some View {
        let x = xPosition(time, width: width)
        let moving = drag.dragging == time
        return VStack(spacing: 0) {
            Text(time.clock)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WinTheme.text)
                .monospacedDigit()
                .frame(width: 80, height: 18)
            Rectangle().fill(WinTheme.amber).frame(width: 2, height: 24).padding(.top, 4)
            Circle().fill(WinTheme.amber).frame(width: 12, height: 12)
        }
        .frame(width: 80, height: 58, alignment: .top)
        .overlay(alignment: .top) {
            // The grab area is the pin itself, not the label.
            Color.clear
                .frame(width: 24, height: 58)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            drag.dragging = time
                            drag.offset = value.translation.width
                        }
                        .onEnded { value in
                            let target = min(max(x + value.translation.width, 0), width)
                            drag.dragging = nil
                            drag.offset = 0
                            onMove(time, minuteOfDay(atX: target, width: width))
                        }
                )
        }
        .offset(x: x - 40 + (moving ? drag.offset : 0), y: 0)
    }

    private func xPosition(_ time: ScheduleTime, width: CGFloat) -> CGFloat {
        CGFloat(time.hour * 60 + time.minute) / 1440 * width
    }

    private func fraction(of date: Date) -> CGFloat {
        let cal = Calendar.current
        let minute = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        return CGFloat(minute) / 1440
    }

    private func minuteOfDay(atX x: CGFloat, width: CGFloat) -> Int {
        let minute = Int((x / max(width, 1)) * 1440)
        return min(max(minute, 0), 1439)
    }
}
