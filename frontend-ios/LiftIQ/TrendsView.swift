//
//  TrendsView.swift
//  LiftIQ
//
//  Cross-session progress charts (Swift Charts).
//

import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trends").font(.system(size: 30, weight: .heavy))
                            Text("Across \(store.sessions.count) sessions")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }

                        let points = store.trendPoints

                        GlassCard(label: "Form score over time") {
                            Chart(points) { p in
                                if let score = p.score {
                                    AreaMark(x: .value("Date", p.date), y: .value("Score", score))
                                        .foregroundStyle(
                                            LinearGradient(colors: [Theme.accent.opacity(0.3), .clear],
                                                           startPoint: .top, endPoint: .bottom))
                                    LineMark(x: .value("Date", p.date), y: .value("Score", score))
                                        .foregroundStyle(Theme.accent)
                                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                    PointMark(x: .value("Date", p.date), y: .value("Score", score))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .frame(height: 170)
                        }

                        GlassCard(label: "Average squat depth (knee angle at bottom — lower is deeper)") {
                            Chart(points) { p in
                                if let d = p.avgDepth {
                                    LineMark(x: .value("Date", p.date), y: .value("Depth", d))
                                        .foregroundStyle(Theme.good)
                                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                    PointMark(x: .value("Date", p.date), y: .value("Depth", d))
                                        .foregroundStyle(Theme.good)
                                }
                            }
                            .frame(height: 170)
                        }

                        GlassCard(label: "Flagged rep rate") {
                            Chart(points) { p in
                                LineMark(x: .value("Date", p.date), y: .value("Flag %", p.flagRate))
                                    .foregroundStyle(Theme.bad)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                PointMark(x: .value("Date", p.date), y: .value("Flag %", p.flagRate))
                                    .foregroundStyle(Theme.bad)
                            }
                            .frame(height: 170)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}
