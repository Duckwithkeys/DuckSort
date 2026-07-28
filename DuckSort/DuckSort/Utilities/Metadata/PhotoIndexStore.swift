//
//  PhotoIndexStore.swift
//  DuckSort
//
//  High-performance spatial and temporal index store for photo collections.
//  Replaces linear scans with fast dictionary lookups and Geohash binning.
//

import Foundation
import Accelerate

final class PhotoIndexStore: @unchecked Sendable {
    private let lock = NSLock()
    
    private var byID: [UUID: PhotoSet] = [:]
    private var byRating: [Int: Set<UUID>] = [:]
    private var byPick: [Int: Set<UUID>] = [:]
    private var geohashBins: [String: Set<UUID>] = [:]
    private var featurePrints: [UUID: [Float]] = [:]
    
    func index(_ photoSets: [PhotoSet]) {
        lock.lock()
        defer { lock.unlock() }
        
        for photo in photoSets {
            byID[photo.id] = photo
            
            if let rating = photo.rating {
                byRating[rating, default: []].insert(photo.id)
            }
            if let pick = photo.pick {
                byPick[pick, default: []].insert(photo.id)
            }
        }
    }

    func indexFeaturePrint(id: UUID, vector: [Float]) {
        guard !vector.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        featurePrints[id] = vector
    }

    /// Computes cosine similarity between two float vectors using Accelerate vDSP.
    private func cosineSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count, !v1.isEmpty else { return 0.0 }
        var dot: Float = 0.0
        var norm1: Float = 0.0
        var norm2: Float = 0.0

        vDSP_dotpr(v1, 1, v2, 1, &dot, vDSP_Length(v1.count))
        vDSP_svesq(v1, 1, &norm1, vDSP_Length(v1.count))
        vDSP_svesq(v2, 1, &norm2, vDSP_Length(v2.count))

        let denom = sqrt(norm1) * sqrt(norm2)
        guard denom > 0 else { return 0.0 }
        return dot / denom
    }

    /// Finds indexed photos matching or exceeding a visual similarity threshold.
    func findSimilarPhotos(to id: UUID, similarityThreshold: Float = 0.85) -> [PhotoSet] {
        lock.lock()
        guard let targetVector = featurePrints[id] else {
            lock.unlock()
            return []
        }
        let allPrints = featurePrints
        let allPhotos = byID
        lock.unlock()

        var results: [PhotoSet] = []
        for (otherID, otherVector) in allPrints where otherID != id {
            let similarity = cosineSimilarity(targetVector, otherVector)
            if similarity >= similarityThreshold, let photo = allPhotos[otherID] {
                results.append(photo)
            }
        }
        return results
    }
    
    func photo(for id: UUID) -> PhotoSet? {
        lock.lock()
        defer { lock.unlock() }
        return byID[id]
    }
    
    func photos(matchingRating rating: Int) -> [PhotoSet] {
        lock.lock()
        defer { lock.unlock() }
        guard let ids = byRating[rating] else { return [] }
        return ids.compactMap { byID[$0] }
    }
    
    func indexSpatial(id: UUID, latitude: Double, longitude: Double) {
        let hash = geohash(lat: latitude, lon: longitude, precision: 5)
        lock.lock()
        defer { lock.unlock() }
        geohashBins[hash, default: []].insert(id)
    }
    
    func photosInSpatialBin(lat: Double, lon: Double) -> [PhotoSet] {
        let hash = geohash(lat: lat, lon: lon, precision: 5)
        lock.lock()
        defer { lock.unlock() }
        guard let ids = geohashBins[hash] else { return [] }
        return ids.compactMap { byID[$0] }
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        byID.removeAll()
        byRating.removeAll()
        byPick.removeAll()
        geohashBins.removeAll()
        featurePrints.removeAll()
    }
    
    // MARK: - Geohash Helper
    
    private func geohash(lat: Double, lon: Double, precision: Int) -> String {
        // Basic geohash discretization algorithm
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var latInterval = (-90.0, 90.0)
        var lonInterval = (-180.0, 180.0)
        var geohash = ""
        var isEven = true
        var bit = 0
        var ch = 0
        
        while geohash.count < precision {
            if isEven {
                let mid = (lonInterval.0 + lonInterval.1) / 2
                if lon > mid {
                    ch |= (1 << (4 - bit))
                    lonInterval.0 = mid
                } else {
                    lonInterval.1 = mid
                }
            } else {
                let mid = (latInterval.0 + latInterval.1) / 2
                if lat > mid {
                    ch |= (1 << (4 - bit))
                    latInterval.0 = mid
                } else {
                    latInterval.1 = mid
                }
            }
            isEven.toggle()
            if bit < 4 {
                bit += 1
            } else {
                geohash.append(base32[ch])
                bit = 0
                ch = 0
            }
        }
        return geohash
    }
}
