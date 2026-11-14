import SwiftUI
import SwiftData

/// Food Book is retiring; the supplement Stack lives in Pulse Lab now.
/// This sends the whole stack (names, doses, emoji, times, order) to Pulse Lab in one tap.
struct StackMoveOffer: ViewModifier {
    @Environment(\.modelContext) private var context
    @AppStorage("stackMovedToPulseLab") private var moved = false
    @State private var show = false
    @State private var count = 0

    func body(content: Content) -> some View {
        content
            .task {
                let n = (try? context.fetchCount(FetchDescriptor<Supplement>())) ?? 0
                count = n
                if n > 0 && !moved { try? await Task.sleep(nanoseconds: 1_200_000_000); show = true }
            }
            .sheet(isPresented: $show) { sheet.presentationDetents([.medium]) }
    }

    private var sheet: some View {
        VStack(spacing: 16) {
            Text("💊").font(.system(size: 52))
            Text("Your Stack moved to Pulse Lab").font(.system(size: 24, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
            Text("Tap once to bring all \(count) supplements over, with the same doses and times. Pulse Lab also logs them to Apple Health and shows how they line up with your WHOOP recovery.")
                .font(.system(size: 15, design: .rounded)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = Self.link(context) {
                    UIApplication.shared.open(url) { ok in if ok { moved = true; show = false } }
                }
            } label: {
                Text("Move my stack to Pulse Lab")
                    .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Capsule().fill(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)))
            }
            Button("Later") { show = false }.font(.system(size: 15, design: .rounded))
        }
        .padding(24)
    }

    /// pulselab://stack-import?d=<base64url JSON>
    static func link(_ context: ModelContext) -> URL? {
        let supps = (try? context.fetch(FetchDescriptor<Supplement>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let items: [[String: Any]] = supps.map {
            ["n": $0.name, "d": $0.dose, "e": $0.emoji, "t": $0.timeRaw, "o": $0.order, "f": $0.withFood]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items) else { return nil }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "pulselab://stack-import?d=\(b64)")
    }
}
