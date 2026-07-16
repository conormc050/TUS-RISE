//
//  AnalyzeView.swift
//  TUS-RISE
//
//  Import session_*.json exported by VidCalc.py. In the final app
//  this screen becomes on-device capture + analysis.
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct AnalyzeView: View {
    @EnvironmentObject private var store: SessionStore

    // JSON comes from Files (document picker); videos come from the photo
    // library — that's where camera recordings live on a real device.
    @State private var showImporter = false
    @State private var showVideoPicker = false
    @State private var pickedVideo: PhotosPickerItem?

    @State private var analysisProgress: Double?
    @State private var imported: LiftSession?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Analyze").font(.system(size: 30, weight: .heavy))
                            Text("Import results from the analysis pipeline")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }

                        // Import zone
                        Button { showImporter = true } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 38, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                                Text("Import session JSON")
                                    .font(.system(size: 16, weight: .heavy))
                                Text("Select a session_*.json file\nexported by VidCalc.py")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Theme.accent.opacity(0.5),
                                                  style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                                    .background(Theme.accent.opacity(0.06),
                                                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            )
                        }
                        .buttonStyle(.plain)

                        // Video analysis zone (step 3 of the port: Vision 3D pose)
                        Button { showVideoPicker = true } label: {
                            VStack(spacing: 10) {
                                if let p = analysisProgress {
                                    ProgressView(value: p)
                                        .tint(Theme.accent)
                                        .padding(.horizontal, 30)
                                    Text("Analysing… \(Int(p * 100))%")
                                        .font(.system(size: 16, weight: .heavy))
                                    Text("Running Apple's 3D body-pose model\nframe by frame")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Image(systemName: "video.badge.waveform")
                                        .font(.system(size: 38, weight: .medium))
                                        .foregroundStyle(Theme.accentDeep)
                                    Text("Analyze video (beta)")
                                        .font(.system(size: 16, weight: .heavy))
                                    Text("Run 3D body-pose analysis on an mp4/mov.\nKnee & hip angles only for now — no reps or flags yet.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Theme.accentDeep.opacity(0.5),
                                                  style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                                    .background(Theme.accentDeep.opacity(0.06),
                                                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(analysisProgress != nil)

                        GlassCard(label: "How it works") {
                            VStack(spacing: 0) {
                                StepRow(num: "1", text: "Record your set from a **side-on view** with the whole body in frame, standing still for the first ~2 seconds (calibration).")
                                Divider().opacity(0.4)
                                StepRow(num: "2", text: "Run **VidCalc.py** on the video. It exports `session_<name>.json` next to the annotated output.")
                                Divider().opacity(0.4)
                                StepRow(num: "3", text: "Import the JSON here to see your form score, flags, and full joint-angle breakdown.")
                            }
                        }

                        GlassCard(label: "Coming to the iOS app") {
                            VStack(spacing: 0) {
                                StepRow(num: "📱", text: "**Record in-app** — capture and analyse directly on-device.")
                                Divider().opacity(0.4)
                                StepRow(num: "⚡", text: "**Live mode** — real-time flags while you lift.")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                do { imported = try store.importSession(from: url) }
                catch { importError = "Couldn't read that file — is it a session_*.json?" }
            }
            .photosPicker(isPresented: $showVideoPicker,
                          selection: $pickedVideo,
                          matching: .videos)
            .onChange(of: pickedVideo) { _, item in
                guard let item else { return }
                pickedVideo = nil
                analyzeVideo(item)
            }
            .sheet(item: $imported) { SessionDetailView(session: $0) }
            .alert("Import failed", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func analyzeVideo(_ item: PhotosPickerItem) {
        analysisProgress = 0
        Task {
            do {
                guard let picked = try await item.loadTransferable(type: PickedVideo.self) else {
                    throw CocoaError(.fileReadUnknown)
                }
                defer { try? FileManager.default.removeItem(at: picked.url) }

                let payload = try await VideoPoseAnalyzer.analyze(url: picked.url) { p in
                    Task { @MainActor in analysisProgress = p }
                }
                let session = LiftSession(payload: payload)
                store.add(session)
                analysisProgress = nil
                imported = session
            } catch {
                analysisProgress = nil
                importError = "Video analysis failed: \(error.localizedDescription)"
            }
        }
    }
}

/// A video handed over by the Photos picker, copied to a temp file we own.
/// (Photos exports to a transient location that's deleted when the closure
/// returns, so the copy has to happen here, not later.)
nonisolated struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedVideo(url: dest)
        }
    }
}

private struct StepRow: View {
    let num: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(num)
                .font(.system(size: 13, weight: .heavy))
                .frame(width: 28, height: 28)
                .background(Theme.accent.opacity(0.14), in: Circle())
                .foregroundStyle(Theme.accentStrong)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }
}
