//
//  HistoryView.swift
//  TUS-RISE
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var filter: Filter = .all
    @State private var selected: LiftSession?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", squat = "Squat", deadlift = "Deadlift", flagged = "⚑ Flagged"
        var id: String { rawValue }
    }

    private var filtered: [LiftSession] {
        switch filter {
        case .all:      return store.sorted
        case .squat:    return store.sorted.filter { $0.exercise == "squat" }
        case .deadlift: return store.sorted.filter { $0.exercise == "deadlift" }
        case .flagged:  return store.sorted.filter { $0.flaggedReps > 0 }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("History").font(.system(size: 30, weight: .heavy))
                            Text("\(store.sessions.count) analysed sessions")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Filter.allCases) { f in
                                    Button {
                                        withAnimation(.snappy) { filter = f }
                                    } label: {
                                        Text(f.rawValue)
                                            .font(.system(size: 13, weight: .semibold))
                                            .padding(.horizontal, 15).padding(.vertical, 8)
                                            .background(
                                                filter == f
                                                ? AnyShapeStyle(Theme.accentGradient)
                                                : AnyShapeStyle(.ultraThinMaterial),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(filter == f ? Color.black.opacity(0.8) : .secondary)
                                    }
                                }
                            }
                        }

                        if filtered.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 40)).foregroundStyle(.tertiary)
                                Text("No sessions here")
                                    .font(.headline)
                                Text("Run VidCalc.py on a video and import\nthe session JSON from the Analyze tab.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(filtered) { s in
                                    Button { selected = s } label: { SessionRow(session: s) }
                                        .buttonStyle(.plain)
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
