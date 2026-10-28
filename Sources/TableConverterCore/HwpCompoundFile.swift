import Foundation

enum HwpNativeReadError: Error { case invalidData }

/// A bounded, read-only MS-CFB reader for the HWP clipboard's FileHeader and BodyText streams.
/// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/
struct HwpCompoundFile {
    private struct Entry {
        let name: String
        let type: UInt8
        let left: UInt32
        let right: UInt32
        let child: UInt32
        let start: UInt32
        let size: Int
    }

    private static let end: UInt32 = 0xfffffffe
    private static let free: UInt32 = 0xffffffff
    static let byteLimit = 64 * 1024 * 1024
    private let bytes: [UInt8]
    private var sectorSize = 512
    private var fat: [UInt32] = []
    private var miniFat: [UInt32] = []
    private var miniStream: [UInt8] = []
    private var entries: [Entry] = []

    init(_ data: Data) throws {
        guard data.count >= 512, data.count <= Self.byteLimit else { throw HwpNativeReadError.invalidData }
        bytes = Array(data)
        guard Array(bytes.prefix(8)) == [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1],
              try bytes.hwpUInt16(28) == 0xfffe,
              try bytes.hwpUInt16(32) == 6,
              try bytes.hwpUInt32(56) == 4096 else { throw HwpNativeReadError.invalidData }
        let version = try bytes.hwpUInt16(26)
        let shift = try bytes.hwpUInt16(30)
        guard (version == 3 && shift == 9) || (version == 4 && shift == 12) else {
            throw HwpNativeReadError.invalidData
        }
        sectorSize = 1 << Int(shift)
        guard bytes.count >= sectorSize, bytes.count % sectorSize == 0 else { throw HwpNativeReadError.invalidData }
        let sectorCount = bytes.count / sectorSize - 1
        let fatCount = Int(try bytes.hwpUInt32(44))
        let difatCount = Int(try bytes.hwpUInt32(72))
        guard fatCount > 0, fatCount <= sectorCount, difatCount <= sectorCount else {
            throw HwpNativeReadError.invalidData
        }
        var fatSectors: [UInt32] = []
        for offset in stride(from: 76, to: 512, by: 4) {
            let id = try bytes.hwpUInt32(offset)
            if id != Self.free { fatSectors.append(id) }
        }
        guard fatSectors.count <= fatCount else { throw HwpNativeReadError.invalidData }
        var difatID = try bytes.hwpUInt32(68)
        var visited = Set<UInt32>()
        for _ in 0..<difatCount {
            guard visited.insert(difatID).inserted else { throw HwpNativeReadError.invalidData }
            let data = try sector(difatID)
            for offset in stride(from: 0, to: sectorSize - 4, by: 4) {
                let id = try data.hwpUInt32(offset)
                if id != Self.free { fatSectors.append(id) }
            }
            guard fatSectors.count <= fatCount else { throw HwpNativeReadError.invalidData }
            difatID = try data.hwpUInt32(sectorSize - 4)
        }
        guard fatSectors.count == fatCount, Set(fatSectors).count == fatCount,
              difatCount == 0 || difatID == Self.end else { throw HwpNativeReadError.invalidData }
        for id in fatSectors {
            let data = try sector(id)
            for offset in stride(from: 0, to: sectorSize, by: 4) { fat.append(try data.hwpUInt32(offset)) }
        }
        let directory = try regularStream(start: bytes.hwpUInt32(48), size: nil)
        for offset in stride(from: 0, to: directory.count, by: 128) {
            let type = directory[offset + 66]
            let nameLength = Int(try directory.hwpUInt16(offset + 64))
            guard type == 0 || (nameLength >= 2 && nameLength <= 64 && nameLength % 2 == 0) else {
                throw HwpNativeReadError.invalidData
            }
            var name: [UInt16] = []
            if type != 0 {
                for index in stride(from: offset, to: offset + nameLength - 2, by: 2) {
                    name.append(try directory.hwpUInt16(index))
                }
            }
            let lowSize = UInt64(try directory.hwpUInt32(offset + 120))
            let highSize = version == 4 ? UInt64(try directory.hwpUInt32(offset + 124)) << 32 : 0
            // Unused directory entries need not describe a stream.
            let size = type == 0 ? 0 : lowSize | highSize
            guard size <= Self.byteLimit else { throw HwpNativeReadError.invalidData }
            entries.append(Entry(name: String(decoding: name, as: UTF16.self), type: type,
                                 left: try directory.hwpUInt32(offset + 68), right: try directory.hwpUInt32(offset + 72),
                                 child: try directory.hwpUInt32(offset + 76), start: try directory.hwpUInt32(offset + 116),
                                 size: Int(size)))
        }
        guard let root = entries.first, root.type == 5 else { throw HwpNativeReadError.invalidData }
        let miniFatCount = Int(try bytes.hwpUInt32(64))
        guard miniFatCount <= sectorCount else { throw HwpNativeReadError.invalidData }
        if miniFatCount > 0 {
            let data = try regularStream(start: bytes.hwpUInt32(60), size: miniFatCount * sectorSize)
            for offset in stride(from: 0, to: data.count, by: 4) { miniFat.append(try data.hwpUInt32(offset)) }
        }
        if root.size > 0 { miniStream = try regularStream(start: root.start, size: root.size) }
    }

    func stream(_ path: [String]) throws -> [UInt8] {
        let entry = try find(path)
        guard entry.type == 2 else { throw HwpNativeReadError.invalidData }
        if entry.size == 0 { return [] }
        if entry.size < 4096 {
            return try Self.chain(start: entry.start, allocation: miniFat, source: miniStream,
                                  unitSize: 64, baseOffset: 0, size: entry.size)
        }
        return try regularStream(start: entry.start, size: entry.size)
    }

    func sectionNames() throws -> [String] {
        let body = try find(["BodyText"])
        guard body.type == 1 else { throw HwpNativeReadError.invalidData }
        let names = try children(body).filter { $0.type == 2 && $0.name.hasPrefix("Section") }
            .compactMap { entry -> (String, Int)? in
                guard let number = Int(entry.name.dropFirst(7)), number >= 0 else { return nil }
                return (entry.name, number)
            }.sorted { $0.1 < $1.1 }
        guard !names.isEmpty, names.count <= 1024 else { throw HwpNativeReadError.invalidData }
        return names.map(\.0)
    }

    private func find(_ path: [String]) throws -> Entry {
        var entry = entries[0]
        for name in path {
            guard let child = try children(entry).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw HwpNativeReadError.invalidData
            }
            entry = child
        }
        return entry
    }

    private func children(_ parent: Entry) throws -> [Entry] {
        var pending = [parent.child]
        var visited = Set<UInt32>()
        var result: [Entry] = []
        while let id = pending.popLast() {
            if id == Self.free { continue }
            guard Int(id) < entries.count, visited.insert(id).inserted else { throw HwpNativeReadError.invalidData }
            let entry = entries[Int(id)]
            guard entry.type == 1 || entry.type == 2 else { throw HwpNativeReadError.invalidData }
            result.append(entry)
            pending.append(contentsOf: [entry.left, entry.right])
        }
        return result
    }

    private func sector(_ id: UInt32) throws -> [UInt8] {
        let offset = (Int(id) + 1) * sectorSize
        guard offset <= bytes.count - sectorSize else { throw HwpNativeReadError.invalidData }
        return Array(bytes[offset..<offset + sectorSize])
    }

    private func regularStream(start: UInt32, size: Int?) throws -> [UInt8] {
        try Self.chain(start: start, allocation: fat, source: bytes, unitSize: sectorSize, baseOffset: sectorSize, size: size)
    }

    private static func chain(start: UInt32, allocation: [UInt32], source: [UInt8], unitSize: Int,
                              baseOffset: Int, size: Int?) throws -> [UInt8] {
        if size == 0 { return [] }
        var id = start
        var visited = Set<UInt32>()
        var output: [UInt8] = []
        while id != end {
            let offset = baseOffset + Int(id) * unitSize
            guard Int(id) < allocation.count, offset <= source.count - unitSize,
                  visited.insert(id).inserted, output.count <= (size ?? byteLimit) - 1 else {
                throw HwpNativeReadError.invalidData
            }
            output.append(contentsOf: source[offset..<offset + unitSize])
            id = allocation[Int(id)]
        }
        if let size {
            guard output.count >= size, output.count - size < unitSize else { throw HwpNativeReadError.invalidData }
            output.removeLast(output.count - size)
        }
        return output
    }
}

extension Array where Element == UInt8 {
    func hwpUInt16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= count - 2 else { throw HwpNativeReadError.invalidData }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func hwpUInt32(_ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= count - 4 else { throw HwpNativeReadError.invalidData }
        return UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
