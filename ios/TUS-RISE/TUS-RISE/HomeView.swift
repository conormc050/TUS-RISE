//
//  HomeView.swift
//  TUS-RISE
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: SessionStore
    @AppStorage("tusrise.athlete") private var athlete = "Athlete"
    @State private var selected: LiftSession?

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(greeting),")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(athlete)
                                .font(.system(size: 30, weight: .heavy))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let latest = store.latest {
                            Button { selected = latest } label: {
                                GlassCard {
                                    HStack(spacing: 18) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("LATEST SESSION")
                                                .font(.system(size: 12, weight: .bold))
                                                .kerning(1.2)
                                                .foregroundStyle(Theme.accent)
                                            Text("\(latest.exercise.capitalized) · \(latest.repCount) reps")
                                                .font(.system(size: 20, weight: .heavy))
                                            Text(latest.flaggedReps > 0
                                                 ? "\(latest.flaggedReps) rep(s) flagged"
                                                 : "All reps clean")
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        ScoreRing(score: latest.score, size: 92)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        let wk = store.weekStats
                        HStack(spacing: 12) {
                            StatTile(value: "\(wk.sessions)", unit: nil, name: "Sessions this week")
                            StatTile(value: "\(wk.reps)", unit: nil, name: "Total reps")
                            StatTile(value: wk.avgScore.map(String.init) ?? "–", unit: nil, name: "Avg score")
                        }

                        if store.sorted.isEmpty {
                            GlassCard(label: "Get started") {
                                Text("No sessions yet — analyse a video from the Analyze tab to get started.")
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            GlassCard(label: "Recent sessions") {
                                VStack(spacing: 10) {
                                    ForEach(store.sorted.prefix(4)) { s in
                                        Button { selected = s } label: { SessionRow(session: s) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .sheet(item: $selected) { SessionDetailView(session: $0) }
        }
    }
}
