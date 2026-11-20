//
//  InsightsCalculator.swift
//  PhotomatorSort
//
//  Computes the photography gear and exposure distribution report from
//  loaded EXIF metadata snapshots and photo set culling flags.
//

import Foundation

enum InsightsCalculator {

    static func compute(
        photoMetadata: [UUID: MetadataSnapshot],
        photoSets: [PhotoSet],
        photoSetIndex: [UUID: Int]
    ) -> InsightReport {
        let total = photoMetadata.count

        // Single pass over photoMetadata to compute unique gear, date range,
        // exposure histograms, and top (camera, lens) combinations.
        var uniqueCameras = Set<String>()
        var uniqueLenses = Set<String>()
        var earliest: Date? = nil
        var latest: Date? = nil

        let focalBucketLabels = ["≤24mm", "25–35mm", "36–50mm", "51–85mm", "86–135mm", "135mm+"]
        var focalCounts = [0, 0, 0, 0, 0, 0]

        let apertureBucketLabels = ["f/1.4", "f/1.8–f/2", "f/2.8", "f/4", "f/5.6–f/8", "f/11+"]
        var apertureCounts = [0, 0, 0, 0, 0, 0]

        let isoBucketLabels = ["ISO 100–400", "ISO 400–800", "ISO 800–1600", "ISO 1600–3200", "ISO 3200+"]
        var isoCounts = [0, 0, 0, 0, 0]

        let shutterBucketLabels = ["1/4000+", "1/1000–1/4000", "1/250–1/1000", "1/60–1/250", "<1/60"]
        var shutterCounts = [0, 0, 0, 0, 0]

        struct ComboKey: Hashable { let camera: String; let lens: String }
        struct ComboData { var count: Int; var picks: Int; var apertures: [Double] }
        var comboMap: [ComboKey: ComboData] = [:]

        for (id, m) in photoMetadata {
            if let cam = m.cameraModel { uniqueCameras.insert(cam) }
            if let lens = m.lensModel { uniqueLenses.insert(lens) }

            if let date = m.captureDate {
                if earliest == nil || date < earliest! { earliest = date }
                if latest == nil || date > latest! { latest = date }
            }

            // Continuous ranges so fractional zoom focal lengths (e.g. 24.5mm, 50.2mm)
            // never fall through to "135mm+".
            if let fl = m.focalLength {
                switch fl {
                case ...24.0:           focalCounts[0] += 1
                case ..<35.5:           focalCounts[1] += 1
                case ..<50.5:           focalCounts[2] += 1
                case ..<85.5:           focalCounts[3] += 1
                case ...135.0:          focalCounts[4] += 1
                default:                focalCounts[5] += 1
                }
            }

            if let ap = m.aperture {
                switch ap {
                case ..<1.6:            apertureCounts[0] += 1 // f/1.4 (and faster)
                case 1.6..<2.4:         apertureCounts[1] += 1 // f/1.8–f/2
                case 2.4..<3.5:         apertureCounts[2] += 1 // f/2.8
                case 3.5..<4.5:         apertureCounts[3] += 1 // f/4
                case 4.5..<10.0:        apertureCounts[4] += 1 // f/5.6–f/8
                default:                apertureCounts[5] += 1 // f/11+
                }
            }

            if let iso = m.iso {
                switch iso {
                case ...399:            isoCounts[0] += 1
                case 400...799:         isoCounts[1] += 1
                case 800...1599:        isoCounts[2] += 1
                case 1600...3199:       isoCounts[3] += 1
                default:                isoCounts[4] += 1
                }
            }

            if let ss = m.shutterSpeed, ss > 0 {
                switch ss {
                case ..<(1.0 / 4000):              shutterCounts[0] += 1
                case (1.0 / 4000)..<(1.0 / 1000):  shutterCounts[1] += 1
                case (1.0 / 1000)..<(1.0 / 250):   shutterCounts[2] += 1
                case (1.0 / 250)..<(1.0 / 60):     shutterCounts[3] += 1
                default:                           shutterCounts[4] += 1
                }
            }

            if let cam = m.cameraModel, let lens = m.lensModel {
                let key = ComboKey(camera: cam, lens: lens)
                let isPick = photoSetIndex[id].map { photoSets[$0].pick == 1 } ?? false
                var data = comboMap[key] ?? ComboData(count: 0, picks: 0, apertures: [])
                data.count += 1
                if isPick { data.picks += 1 }
                if let ap = m.aperture { data.apertures.append(ap) }
                comboMap[key] = data
            }
        }

        let cameras = uniqueCameras.count
        let lenses = uniqueLenses.count

        let focalTotal = focalCounts.reduce(0, +)
        let focalBuckets = zip(focalBucketLabels, focalCounts).map { label, count in
            InsightBucket(label: label, count: count, percentage: focalTotal > 0 ? Double(count) / Double(focalTotal) : 0)
        }

        let apTotal = apertureCounts.reduce(0, +)
        let apertureBuckets = zip(apertureBucketLabels, apertureCounts).map { label, count in
            InsightBucket(label: label, count: count, percentage: apTotal > 0 ? Double(count) / Double(apTotal) : 0)
        }

        let isoTotal = isoCounts.reduce(0, +)
        let isoBuckets = zip(isoBucketLabels, isoCounts).map { label, count in
            InsightBucket(label: label, count: count, percentage: isoTotal > 0 ? Double(count) / Double(isoTotal) : 0)
        }

        let shutterTotal = shutterCounts.reduce(0, +)
        let shutterBuckets = zip(shutterBucketLabels, shutterCounts).map { label, count in
            InsightBucket(label: label, count: count, percentage: shutterTotal > 0 ? Double(count) / Double(shutterTotal) : 0)
        }

        let topCombos = comboMap
            .sorted { $0.value.count > $1.value.count }
            .prefix(8)
            .map { (key, data) in
                GearCombo(
                    camera: key.camera,
                    lens: key.lens,
                    totalShots: data.count,
                    pickRatio: data.count > 0 ? Double(data.picks) / Double(data.count) : 0,
                    avgAperture: data.apertures.isEmpty ? nil : data.apertures.reduce(0, +) / Double(data.apertures.count)
                )
            }

        return InsightReport(
            totalPhotos: total,
            uniqueCameras: cameras,
            uniqueLenses: lenses,
            earliestDate: earliest,
            latestDate: latest,
            focalLengthBuckets: focalBuckets,
            apertureBuckets: apertureBuckets,
            isoBuckets: isoBuckets,
            shutterBuckets: shutterBuckets,
            topGearCombos: topCombos
        )
    }
}
