import Foundation

enum PetName {
    static func normalized(_ proposedName: String) -> String? {
        let name = proposedName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty, name.count <= 24,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return name
    }
}
