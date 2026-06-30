//
//  EXIFAnalyticsView.swift
//  DuckSort
//
//  Native telemetry and analytics dashboard aggregating EXIF metadata distributions
//  and gear performance ratings across indexed photosets.
//

import SwiftUI
import Charts

struct EXIFAnalyticsView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Dashboard Header
            headerBar
                .padding(.horizontal, Theme.Space.s24)
                .padding(.top, Theme.Space.s24)
                .padding(.bottom, Theme.Space.s16)

            Divider()
                .background(Theme.Color.separator)

            if viewModel.photoMetadata.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.Space.s20) {
                        // Top Grid: 3 Distributions
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Space.s20) {
                            chartCard(title: "Focal Length Distribution", systemImage: "viewfinder") {
                                focalLengthChart
                            }
                            chartCard(title: "Aperture Sensitivity Profile", systemImage: "camera.aperture") {
                                apertureChart
                            }
                            chartCard(title: "ISO Sensitivity Profile", systemImage: "sensor.fill") {
                                isoChart
                            }
                            chartCard(title: "Highest Performing Gear (5★ Ratio)", systemImage: "crown.fill") {
                                gearPerformanceList
                            }
                        }
                    }
                    .padding(Theme.Space.s24)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.background)
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text("Camera & Lens Insights")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Aggregated EXIF telemetry from \(viewModel.photoMetadata.count) analyzed photo set\(viewModel.photoMetadata.count == 1 ? "" : "s")")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s16) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("No Analytics Available")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textSecondary)
            Text("Import folders with photos containing EXIF metadata to view shooting insights.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chartCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Color.accent)
                Text(title)
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            .padding(.bottom, 4)

            content()
                .frame(minHeight: 180, maxHeight: 220)
        }
        .padding(Theme.Space.s16)
        .background(Theme.Color.cellBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.l)
                .strokeBorder(Theme.Color.separator, lineWidth: 1)
        )
    }

    // MARK: - Telemetry Charts

    private var focalLengthChart: some View {
        let data = focalLengthDistribution
        return Group {
            if data.isEmpty {
                noTelemetryLabel
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Focal Length", item.label),
                        y: .value("Shots", item.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.Color.accent, Theme.Color.accent.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(Theme.Radius.s)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
        }
    }

    private var apertureChart: some View {
        let data = apertureDistribution
        return Group {
            if data.isEmpty {
                noTelemetryLabel
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Aperture", item.label),
                        y: .value("Shots", item.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.Color.success, Theme.Color.success.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(Theme.Radius.s)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
        }
    }

    private var isoChart: some View {
        let data = isoDistribution
        return Group {
            if data.isEmpty {
                noTelemetryLabel
            } else {
                Chart(data) { item in
                    AreaMark(
                        x: .value("ISO", item.label),
                        y: .value("Shots", item.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.Color.accent.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("ISO", item.label),
                        y: .value("Shots", item.count)
                    )
                    .foregroundStyle(Theme.Color.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
        }
    }

    private var gearPerformanceList: some View {
        let data = gearPerformance.prefix(5)
        return Group {
            if data.isEmpty {
                noTelemetryLabel
            } else {
                VStack(spacing: Theme.Space.s10) {
                    ForEach(data) { combo in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(combo.lens)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Theme.Color.textPrimary)
                                        .lineLimit(1)
                                    Text(combo.camera)
                                        .font(Theme.Font.caption2)
                                        .foregroundStyle(Theme.Color.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(String(format: "%.0f%% 5★", combo.ratio * 100))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.Color.rating)
                            }
                            
                            // Visual horizontal fill bar for rating efficiency
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Theme.Color.separator)
                                        .frame(height: 4)
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(
                                            LinearGradient(
                                                colors: [Theme.Color.rating, Theme.Color.warning],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geometry.size.width * CGFloat(combo.ratio), height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var noTelemetryLabel: some View {
        VStack {
            Spacer()
            Text("Insufficient EXIF Data")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Processing / Data Aggregations

    struct FocalLengthData: Identifiable {
        let value: Double
        let label: String
        let count: Int
        var id: String { label }
    }

    struct ApertureData: Identifiable {
        let value: Double
        let label: String
        let count: Int
        var id: String { label }
    }

    struct ISOData: Identifiable {
        let value: Int
        let label: String
        let count: Int
        var id: String { label }
    }

    struct GearRatingData: Identifiable {
        let camera: String
        let lens: String
        let totalCount: Int
        let fiveStarCount: Int
        var ratio: Double {
            totalCount > 0 ? Double(fiveStarCount) / Double(totalCount) : 0.0
        }
        var id: String { "\(camera)-\(lens)" }
    }

    private var focalLengthDistribution: [FocalLengthData] {
        var counts: [Double: Int] = [:]
        for snapshot in viewModel.photoMetadata.values {
            if let focal = snapshot.focalLength ?? snapshot.focalLengthIn35mm {
                let rounded = round(focal)
                counts[rounded, default: 0] += 1
            }
        }
        return counts.map { FocalLengthData(value: $0.key, label: "\(Int($0.key))mm", count: $0.value) }
            .sorted { $0.value < $1.value }
    }

    private var apertureDistribution: [ApertureData] {
        var counts: [Double: Int] = [:]
        for snapshot in viewModel.photoMetadata.values {
            if let ap = snapshot.aperture {
                let rounded = (ap * 10).rounded() / 10
                counts[rounded, default: 0] += 1
            }
        }
        return counts.map { ApertureData(value: $0.key, label: "f/\($0.key)", count: $0.value) }
            .sorted { $0.value < $1.value }
    }

    private var isoDistribution: [ISOData] {
        var counts: [Int: Int] = [:]
        for snapshot in viewModel.photoMetadata.values {
            if let iso = snapshot.iso {
                counts[iso, default: 0] += 1
            }
        }
        return counts.map { ISOData(value: $0.key, label: "ISO \($0.key)", count: $0.value) }
            .sorted { $0.value < $1.value }
    }

    private var gearPerformance: [GearRatingData] {
        struct GearKey: Hashable {
            let camera: String
            let lens: String
        }
        var counts: [GearKey: (total: Int, fiveStar: Int)] = [:]
        for (photoID, snapshot) in viewModel.photoMetadata {
            let rating = viewModel.photoSets.first(where: { $0.id == photoID })?.rating ?? snapshot.rating
            
            let camera = snapshot.cameraModel ?? "Unknown Body"
            let lens = snapshot.lensModel ?? "Unknown Lens"
            let key = GearKey(camera: camera, lens: lens)
            
            let isFiveStar = rating == 5
            let current = counts[key] ?? (0, 0)
            counts[key] = (current.total + 1, current.fiveStar + (isFiveStar ? 1 : 0))
        }
        return counts.map {
            GearRatingData(
                camera: $0.key.camera,
                lens: $0.key.lens,
                totalCount: $0.value.total,
                fiveStarCount: $0.value.fiveStar
            )
        }
        .sorted {
            if $0.ratio == $1.ratio {
                return $0.totalCount > $1.totalCount
            }
            return $0.ratio > $1.ratio
        }
    }
}
