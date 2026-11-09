import SwiftUI
import UIKit

/// Under the ring: what you burned today (from Apple Health, which includes Whoop and Apple Watch).
struct BurnedStrip: View {
    let health: FoodHealth
    @Binding var net: Bool
    let eatBack: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                stat("ACTIVE", health.active, Ember.orange, "flame.fill")
                stat("RESTING", health.resting, Ember.gold, "bed.double.fill")
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy) { net.toggle() }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: net ? "plusminus.circle.fill" : "plusminus.circle")
                            .font(.system(size: 18, weight: .bold))
                        Text(net ? "NET ON" : "NET").font(Ember.font(9, .heavy)).tracking(1)
                    }
                    .foregroundStyle(net ? .white : Ember.dim)
                    .frame(width: 64, height: 58)
                    .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(net ? AnyShapeStyle(Ember.fire) : AnyShapeStyle(Ember.card)) }
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ember.line))
                }
                .buttonStyle(Squish())
                .accessibilityLabel(net ? "Ring shows eaten minus burned. Tap to show eaten." : "Show eaten minus burned on the ring")
            }
            if !health.workouts.isEmpty || health.exerciseMinutes > 0 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        if health.exerciseMinutes > 0 {
                            chip(symbol: "figure.run.circle.fill", title: "\(Int(health.exerciseMinutes)) min exercise", source: nil)
                        }
                        ForEach(health.workouts) { w in
                            chip(symbol: w.symbol, title: "\(w.name) · \(Int(w.kcal)) cal", source: w.source)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if eatBack > 0 && health.active > 0 {
                Text("Goal includes \(eatBack)% of active calories (+\(Int(health.active * Double(eatBack) / 100)))")
                    .font(Ember.font(11, .semibold)).foregroundStyle(Ember.dim)
            }
            if let p = health.problem {
                Text(p).font(Ember.font(11, .semibold)).foregroundStyle(Ember.pink).multilineTextAlignment(.center)
            }
        }
        .animation(.snappy, value: health.workouts)
    }

    private func stat(_ label: String, _ value: Double, _ color: Color, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                Text("\(Int(value.rounded()))").font(Ember.font(18, .heavy)).foregroundStyle(Ember.cream)
                    .contentTransition(.numericText(value: value))
            }
            Text(label).font(Ember.font(9, .heavy)).tracking(1).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity).frame(height: 58)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.25)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.lowercased()) \(Int(value)) calories")
    }

    private func chip(symbol: String, title: String, source: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Ember.orange)
            Text(title).font(Ember.font(12, .bold)).foregroundStyle(Ember.cream)
            if let source {
                Text(source.uppercased()).font(Ember.font(8, .heavy)).tracking(0.8)
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(source.lowercased().contains("whoop") ? Ember.gold : Ember.cream.opacity(0.85), in: Capsule())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Ember.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Ember.line))
        .accessibilityElement(children: .combine)
    }
}

/// Goal sheet section: connect Apple Health and choose how much burned energy to eat back.
struct HealthSettings: View {
    @State private var health = FoodHealth.shared
    @AppStorage("eatBackPct") private var eatBack: Int = 0
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Apple Health", systemImage: "heart.fill").font(Ember.font(17, .heavy)).foregroundStyle(Ember.cream)
            Text(health.showing
                 ? "On. Meals you log are saved to Health, and today's burned calories and workouts come back from it."
                 : "Save every meal to Apple Health and see what you burned today, from your Apple Watch and Whoop.")
                .font(Ember.font(13, .medium)).foregroundStyle(Ember.dim)
                .fixedSize(horizontal: false, vertical: true)

            if !health.available {
                Text("Apple Health isn't available on this device.").font(Ember.font(12, .semibold)).foregroundStyle(Ember.pink)
            } else if !health.showing {
                Button {
                    busy = true
                    Task { await health.connect(); busy = false }
                } label: {
                    Label(busy ? "Opening Health…" : "Connect Apple Health", systemImage: "heart.circle.fill")
                        .font(Ember.font(15, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(Ember.fire, in: Capsule())
                }
                .buttonStyle(Squish())
                .disabled(busy)
            } else {
                row("Meals to Health", health.canWrite ? "Saving" : "Not allowed — Health → Sharing → Apps → Food Book",
                    ok: health.canWrite)
                row("Burned today", "\(Int(health.active)) active · \(Int(health.resting)) resting", ok: true)

                Text("ADD ACTIVE CALORIES TO MY GOAL").font(Ember.font(10, .heavy)).tracking(1.2).foregroundStyle(Ember.dim)
                    .padding(.top, 6)
                HStack(spacing: 8) {
                    ForEach([0, 50, 100], id: \.self) { pct in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            eatBack = pct
                        } label: {
                            Text(pct == 0 ? "Off" : "\(pct)%")
                                .font(Ember.font(15, .heavy))
                                .foregroundStyle(eatBack == pct ? .white : Ember.cream)
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background { Capsule().fill(eatBack == pct ? AnyShapeStyle(Ember.fire) : AnyShapeStyle(Ember.card)) }
                        }
                        .buttonStyle(Squish())
                        .accessibilityAddTraits(eatBack == pct ? .isSelected : [])
                    }
                }
                Button(role: .destructive) { health.disconnect() } label: {
                    Text("Stop syncing").font(Ember.font(13, .bold)).foregroundStyle(Ember.pink)
                }
                .padding(.top, 2)
            }
            if let p = health.problem {
                Text(p).font(Ember.font(12, .semibold)).foregroundStyle(Ember.orange)
            }
            Text("Whoop data arrives through Apple Health — in the Whoop app, turn on its Apple Health integration.")
                .font(Ember.font(11, .medium)).foregroundStyle(Ember.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ember.line))
    }

    private func row(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Ember.orange)
            Text(title).font(Ember.font(13, .bold)).foregroundStyle(Ember.cream)
            Spacer()
            Text(value).font(Ember.font(12, .medium)).foregroundStyle(Ember.dim).multilineTextAlignment(.trailing)
        }
    }
}
