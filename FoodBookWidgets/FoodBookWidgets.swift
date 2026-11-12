import SwiftUI
import WidgetKit

// Food Book on the Home Screen: calories and protein left today, and water. Tap to snap a meal.
// Self-contained: reads only the App Group written by the app's WidgetBridge.

@main
struct FoodBookWidgets: WidgetBundle {
    var body: some Widget {
        FoodBookTodayWidget()
        if #available(iOS 18.0, *) {
            SnapMealControl()
        }
    }
}

private enum FBShared {
    static let appGroup = "group.com.troydunn.foodbook"
    static let snapURL = URL(string: "foodbook://snap")!

    static func read() -> FBEntry {
        let d = UserDefaults(suiteName: appGroup)
        func v(_ k: String, _ fallback: Double = 0) -> Double { d?.object(forKey: k) == nil ? fallback : (d?.double(forKey: k) ?? fallback) }
        // Numbers are for the day they were written; after midnight show a fresh day.
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian); fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.dateFormat = "yyyy-MM-dd"
        let written = d?.string(forKey: "day") ?? ""
        let isToday = written == fmt.string(from: Date())
        let kcalGoal = v("kcalGoal", 2200), proteinGoal = v("proteinGoal", 150)
        if !isToday {
            return FBEntry(date: Date(), kcal: 0, protein: 0, kcalLeft: kcalGoal, proteinLeft: proteinGoal,
                           kcalGoal: kcalGoal, proteinGoal: proteinGoal, water: 0)
        }
        return FBEntry(date: Date(), kcal: v("kcal"), protein: v("protein"),
                       kcalLeft: v("kcalLeft", kcalGoal), proteinLeft: v("proteinLeft", proteinGoal),
                       kcalGoal: kcalGoal, proteinGoal: proteinGoal, water: v("water"))
    }
}

private enum FBPalette {
    static let bg = Color(red: 0.07, green: 0.05, blue: 0.05)
    static let cream = Color(red: 1.0, green: 0.95, blue: 0.88)
    static let dim = Color(red: 1.0, green: 0.95, blue: 0.88).opacity(0.55)
    static let orange = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let pink = Color(red: 1.0, green: 0.27, blue: 0.47)
    static let gold = Color(red: 1.0, green: 0.8, blue: 0.3)
    static let protein = Color(red: 0.42, green: 0.78, blue: 1.0)
    static let fire = LinearGradient(colors: [gold, orange, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func font(_ s: CGFloat, _ w: Font.Weight = .bold) -> Font { .system(size: s, weight: w, design: .rounded) }
}

struct FBEntry: TimelineEntry {
    let date: Date
    let kcal: Double
    let protein: Double
    let kcalLeft: Double
    let proteinLeft: Double
    let kcalGoal: Double
    let proteinGoal: Double
    let water: Double

    static let sample = FBEntry(date: Date(), kcal: 1_240, protein: 86, kcalLeft: 960, proteinLeft: 64,
                                kcalGoal: 2_200, proteinGoal: 150, water: 4)
}

struct FBProvider: TimelineProvider {
    func placeholder(in context: Context) -> FBEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (FBEntry) -> Void) {
        completion(context.isPreview ? .sample : FBShared.read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FBEntry>) -> Void) {
        // The app reloads this whenever something is saved; also roll over at midnight on our own.
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        completion(Timeline(entries: [FBShared.read()], policy: .after(midnight)))
    }
}

struct FoodBookTodayWidget: Widget {
    let kind = "FoodBookToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FBProvider()) { entry in
            FBTodayView(entry: entry)
                .widgetURL(FBShared.snapURL)
                .containerBackground(for: .widget) { FBPalette.bg }
        }
        .configurationDisplayName("Today")
        .description("Calories and protein left today, and your water. Tap to snap a meal.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FBTodayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FBEntry

    private var kcalProgress: Double { entry.kcalGoal > 0 ? min(1, entry.kcal / entry.kcalGoal) : 0 }
    private var proteinProgress: Double { entry.proteinGoal > 0 ? min(1, entry.protein / entry.proteinGoal) : 0 }
    private var over: Bool { entry.kcalLeft < 0 }

    var body: some View {
        if family == .systemMedium { medium } else { small }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FOOD BOOK").font(FBPalette.font(9, .heavy)).tracking(2).foregroundStyle(FBPalette.orange)
                Spacer()
                Image(systemName: "camera.fill").font(.system(size: 11, weight: .black)).foregroundStyle(FBPalette.cream.opacity(0.6))
            }
            Spacer(minLength: 0)
            Text("\(Int(abs(entry.kcalLeft).rounded()))")
                .font(.system(size: 36, weight: .black, design: .rounded)).foregroundStyle(FBPalette.cream)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(over ? "CAL OVER" : "CAL LEFT").font(FBPalette.font(9, .heavy)).tracking(1.2)
                .foregroundStyle(over ? FBPalette.pink : FBPalette.dim)
            bar(kcalProgress, over ? AnyShapeStyle(FBPalette.pink) : AnyShapeStyle(FBPalette.fire))
            HStack(spacing: 6) {
                Text("\(Int(max(0, entry.proteinLeft).rounded()))g P left")
                    .font(FBPalette.font(11, .heavy)).foregroundStyle(FBPalette.protein)
                Spacer(minLength: 0)
                Label("\(Int(entry.water))", systemImage: "drop.fill").font(FBPalette.font(11, .heavy)).foregroundStyle(FBPalette.protein)
                    .labelStyle(.titleAndIcon)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle().trim(from: 0, to: kcalProgress)
                    .stroke(over ? AnyShapeStyle(FBPalette.pink) : AnyShapeStyle(FBPalette.fire), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(abs(entry.kcalLeft).rounded()))")
                        .font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(FBPalette.cream)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(over ? "OVER" : "LEFT").font(FBPalette.font(8, .heavy)).tracking(1).foregroundStyle(over ? FBPalette.pink : FBPalette.dim)
                }
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("FOOD BOOK").font(FBPalette.font(9, .heavy)).tracking(2).foregroundStyle(FBPalette.orange)
                    Spacer()
                    Label("Snap", systemImage: "camera.fill").font(FBPalette.font(10, .heavy)).foregroundStyle(FBPalette.cream.opacity(0.7))
                }
                row("Calories", "\(Int(entry.kcal)) of \(Int(entry.kcalGoal))", kcalProgress, over ? AnyShapeStyle(FBPalette.pink) : AnyShapeStyle(FBPalette.fire))
                row("Protein", "\(Int(entry.protein))g of \(Int(entry.proteinGoal))g", proteinProgress, AnyShapeStyle(FBPalette.protein))
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(FBPalette.protein)
                    Text("\(Int(entry.water)) glasses · \(Int(entry.water * 250)) ml")
                        .font(FBPalette.font(11, .bold)).foregroundStyle(FBPalette.dim)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ title: String, _ detail: String, _ p: Double, _ style: AnyShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(FBPalette.font(11, .heavy)).foregroundStyle(FBPalette.cream)
                Spacer()
                Text(detail).font(FBPalette.font(10, .bold)).foregroundStyle(FBPalette.dim)
            }
            bar(p, style)
        }
    }

    private func bar(_ p: Double, _ style: AnyShapeStyle) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(style).frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, p)))))
            }
        }
        .frame(height: 6)
    }
}
