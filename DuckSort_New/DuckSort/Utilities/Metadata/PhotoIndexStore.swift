//
//  PhotoIndexStore.swift
//  DuckSort
//
//  High-performance spatial and temporal index store for photo collections.
//  Replaces linear scans with fast dictionary lookups and Geohash binning.
//

import Foundation

final class PhotoIndexStore: @unchecked Sendable {
    private let lock = NSLock()
    
    private var byID: [UUID: PhotoSet] = [:]
    private var byRating: [Int: Set<UUID>] = [:]
    private var byPick: [Int: Set<UUID>] = [:]
    private var geohashBins: [String: Set<UUID>] = [:]
    
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
