import Foundation
import ImageIO
import UIKit

/// A photo belongs to one memory and stays on this device, outside backups.
/// Decode to pixels and re-encode: never retain location or camera metadata.
struct MemoryPhotoStore {
    let storage: PawPacePrivateStorage

    init(directoryURL: URL? = nil) throws {
        if let directoryURL { storage = PawPacePrivateStorage(directoryURL: directoryURL) }
        else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
            storage = PawPacePrivateStorage(directoryURL: support.appendingPathComponent("PawPaceMemoryPhotos"))
        }
    }

    func load(memoryID: String) throws -> Data? { try storage.load(Data.self, named: fileName(memoryID)) }
    func remove(memoryID: String) throws { try storage.remove(named: fileName(memoryID)) }

    @discardableResult
    func save(_ data: Data, memoryID: String) throws -> Data {
        guard data.count <= 25_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_200
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: pixels).jpegData(compressionQuality: 0.82) else { throw PhotoError.invalidImage }
        try storage.save(jpeg, named: fileName(memoryID))
        return jpeg
    }

    private func fileName(_ id: String) throws -> String {
        guard !id.isEmpty, id.count < 160,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" }) else { throw PhotoError.invalidID }
        return "memory-\(id).json"
    }

    enum PhotoError: LocalizedError {
        case invalidImage, invalidID
        var errorDescription: String? {
            switch self {
            case .invalidImage: "Choose a still photo smaller than 25 MB. Your existing photo is safe."
            case .invalidID: "This memory could not be found."
            }
        }
    }
}
