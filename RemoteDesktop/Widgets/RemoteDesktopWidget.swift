import WidgetKit
import SwiftUI

/// Home-screen widget offering quick access to RemoteDesktop.
/// Self-contained (no app types) so the extension compiles independently.

struct RDEntry: TimelineEntry { let date: Date }

struct RDProvider: TimelineProvider {
    func placeholder(in context: Context) -> RDEntry { RDEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (RDEntry) -> Void) {
        completion(RDEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RDEntry>) -> Void) {
        completion(Timeline(entries: [RDEntry(date: .now)], policy: .never))
    }
}

struct RDWidgetEntryView: View {
    var entry: RDEntry
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "display").font(.title2)
            Text("RemoteDesktop").font(.caption.bold())
        }
    }
}

struct RemoteDesktopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RemoteDesktopWidget", provider: RDProvider()) { entry in
            if #available(iOS 17.0, *) {
                RDWidgetEntryView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
            } else {
                RDWidgetEntryView(entry: entry).padding()
            }
        }
        .configurationDisplayName("RemoteDesktop")
        .description("Quick access to your devices.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct RemoteDesktopWidgetBundle: WidgetBundle {
    var body: some Widget { RemoteDesktopWidget() }
}
