import Compression
import Foundation

/// 只读 ZIP 解析器（EPUB 就是 ZIP）。
///
/// 设计取舍：
/// - 不引入第三方依赖，用系统的 `Compression` 框架做 inflate；
/// - 兼容 stored(0) 与 deflate(8) 两种压缩方式，兼容 Zip64 扩展；
/// - 文件映射加载，按需解压单个成员，避免大 EPUB 一次性吃光内存。
final class ZipArchive {
    private struct Entry {
        var name: String
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var dataOffset: Int
        var isDirectory: Bool
    }

    private let raw: Data
    private var entries: [String: Entry] = [:]
    private(set) var entryNames: [String] = []

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        guard data.startIndex == 0 else { return nil }
        self.raw = data
        guard parseCentralDirectory() else { return nil }
    }

    func contains(_ name: String) -> Bool {
        entries[name] != nil
    }

    func firstFile(matching predicate: (String) -> Bool) -> String? {
        entryNames.first(where: predicate)
    }

    func data(forFile name: String) -> Data? {
        guard let entry = entries[name], !entry.isDirectory else { return nil }
        let lower = entry.dataOffset
        let upper = entry.dataOffset + entry.compressedSize
        guard lower >= 0, upper <= raw.count, lower <= upper else { return nil }
        let compressed = raw.subdata(in: lower..<upper)
        switch entry.method {
        case 0:
            return compressed
        case 8:
            return Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    // MARK: - 中央目录

    private func parseCentralDirectory() -> Bool {
        guard let eocd = locateEndOfCentralDirectory() else { return false }
        var cursor = eocd.centralDirectoryOffset
        var parsed = 0
        let total = eocd.entryCount

        while parsed < total, cursor + 46 <= raw.count {
            guard readUInt32(cursor) == 0x0201_4B50 else { break }

            let method = readUInt16(cursor + 10)
            var compressedSize = Int(readUInt32(cursor + 20))
            var uncompressedSize = Int(readUInt32(cursor + 24))
            let nameLength = Int(readUInt16(cursor + 28))
            let extraLength = Int(readUInt16(cursor + 30))
            let commentLength = Int(readUInt16(cursor + 32))
            var localHeaderOffset = Int(readUInt32(cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLength <= raw.count else { break }
            let name = decodeName(at: nameStart, length: nameLength, flags: readUInt16(cursor + 8))

            // Zip64 扩展字段
            var extraCursor = nameStart + nameLength
            let extraEnd = extraCursor + extraLength
            while extraCursor + 4 <= extraEnd {
                let headerID = readUInt16(extraCursor)
                let size = Int(readUInt16(extraCursor + 2))
                if headerID == 0x0001 {
                    var fieldCursor = extraCursor + 4
                    if uncompressedSize == 0xFFFFFFFF, fieldCursor + 8 <= extraEnd {
                        uncompressedSize = Int(readUInt64(fieldCursor))
                        fieldCursor += 8
                    }
                    if compressedSize == 0xFFFFFFFF, fieldCursor + 8 <= extraEnd {
                        compressedSize = Int(readUInt64(fieldCursor))
                        fieldCursor += 8
                    }
                    if localHeaderOffset == 0xFFFFFFFF, fieldCursor + 8 <= extraEnd {
                        localHeaderOffset = Int(readUInt64(fieldCursor))
                        fieldCursor += 8
                    }
                }
                extraCursor += 4 + size
            }

            if !name.isEmpty {
                let isDirectory = name.hasSuffix("/")
                let dataOffset = resolveDataOffset(localHeaderOffset: localHeaderOffset)
                let entry = Entry(
                    name: name,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    dataOffset: dataOffset,
                    isDirectory: isDirectory
                )
                if !isDirectory, entries[name] == nil {
                    entries[name] = entry
                    entryNames.append(name)
                }
            }

            cursor = nameStart + nameLength + extraLength + commentLength
            parsed += 1
        }

        return !entries.isEmpty
    }

    private func resolveDataOffset(localHeaderOffset: Int) -> Int {
        guard localHeaderOffset + 30 <= raw.count,
              readUInt32(localHeaderOffset) == 0x0403_4B50 else {
            return localHeaderOffset
        }
        let nameLength = Int(readUInt16(localHeaderOffset + 26))
        let extraLength = Int(readUInt16(localHeaderOffset + 28))
        return localHeaderOffset + 30 + nameLength + extraLength
    }

    private struct EOCDRecord {
        var entryCount: Int
        var centralDirectoryOffset: Int
    }

    private func locateEndOfCentralDirectory() -> EOCDRecord? {
        let signature: UInt32 = 0x0605_4B50
        let minimum = 22
        var index = raw.count - minimum
        let searchFloor = max(0, raw.count - minimum - 65_536)

        while index >= searchFloor {
            if readUInt32(index) == signature {
                let commentLength = Int(readUInt16(index + 20))
                if index + minimum + commentLength == raw.count {
                    var entryCount = Int(readUInt16(index + 10))
                    var cdOffset = Int(readUInt32(index + 16))

                    if entryCount == 0xFFFF || cdOffset == 0xFFFF_FFFF {
                        if let zip64 = locateZip64EndOfCentralDirectory(before: index) {
                            entryCount = Int(zip64.entryCount)
                            cdOffset = Int(zip64.centralDirectoryOffset)
                        }
                    }
                    return EOCDRecord(entryCount: entryCount, centralDirectoryOffset: cdOffset)
                }
            }
            index -= 1
        }
        return nil
    }

    private func locateZip64EndOfCentralDirectory(before eocdIndex: Int) -> (entryCount: UInt64, centralDirectoryOffset: UInt64)? {
        let locatorIndex = eocdIndex - 20
        guard locatorIndex >= 0, readUInt32(locatorIndex) == 0x0706_4B50 else { return nil }
        guard let recordIndex = Int(exactly: readUInt64(locatorIndex + 8)) else { return nil }
        guard recordIndex >= 0, recordIndex + 56 <= raw.count,
              readUInt32(recordIndex) == 0x0606_4B50 else { return nil }
        return (readUInt64(recordIndex + 32), readUInt64(recordIndex + 48))
    }

    // MARK: - 低层读取

    private func readUInt16(_ offset: Int) -> UInt16 {
        guard offset + 2 <= raw.count else { return 0 }
        return UInt16(raw[offset]) | (UInt16(raw[offset + 1]) << 8)
    }

    private func readUInt32(_ offset: Int) -> UInt32 {
        guard offset + 4 <= raw.count else { return 0 }
        return readUInt16(offset) | (readUInt16(offset + 2) << 16)
    }

    private func readUInt64(_ offset: Int) -> UInt64 {
        guard offset + 8 <= raw.count else { return 0 }
        return readUInt32(offset) | (UInt64(readUInt32(offset + 4)) << 32)
    }

    private func decodeName(at offset: Int, length: Int, flags: UInt16) -> String {
        guard length > 0, offset + length <= raw.count else { return "" }
        let bytes = raw.subdata(in: offset..<(offset + length))
        let usesUTF8 = (flags & 0x0800) != 0
        if usesUTF8, let text = String(data: bytes, encoding: .utf8) { return text }
        if let text = String(data: bytes, encoding: .utf8) { return text }
        return String(data: bytes, encoding: .isoLatin1) ?? ""
    }

    // MARK: - 解压

    /// DEFLATE 解压。系统 Compression 框架的 ZLIB 语义在不同系统版本上
    /// 对「裸 DEFLATE」和「zlib 包裹」处理不一致，这里两种都试，并用预期大小校验结果。
    static func inflate(_ compressed: Data, expectedSize: Int) -> Data? {
        guard expectedSize >= 0, expectedSize < 512 * 1024 * 1024 else { return nil }
        guard !compressed.isEmpty else { return expectedSize == 0 ? Data() : nil }

        if let output = decode(compressed, expectedSize: expectedSize) {
            return output
        }

        // 尝试补上 zlib 头 + adler32
        var wrapped = Data([0x78, 0x9C])
        wrapped.append(compressed)
        let checksum = adler32(of: compressed)
        withUnsafeBytes(of: checksum.bigEndian) { wrapped.append(contentsOf: $0) }
        return decode(wrapped, expectedSize: expectedSize)
    }

    private static func decode(_ input: Data, expectedSize: Int) -> Data? {
        let maximumCapacity = 256 * 1024 * 1024
        var capacity = min(max(expectedSize, 1), maximumCapacity)
        var output = Data(count: capacity)

        for _ in 0..<3 {
            let written = output.withUnsafeMutableBytes { destination -> Int in
                input.withUnsafeBytes { source -> Int in
                    guard
                        let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                        let src = source.bindMemory(to: UInt8.self).baseAddress
                    else { return 0 }
                    return compression_decode_buffer(
                        dst, capacity, src, input.count, nil, COMPRESSION_ZLIB
                    )
                }
            }

            if written > 0 {
                if expectedSize == 0 || written == expectedSize {
                    output.removeSubrange(written..<output.count)
                    return output
                }
                // 缓冲区不够时 written == capacity，扩容重试
                if written == capacity && capacity < maximumCapacity {
                    capacity = min(capacity * 2, maximumCapacity)
                    output = Data(count: capacity)
                    continue
                }
                return nil
            }
            if capacity >= maximumCapacity { return nil }
            capacity = min(capacity * 2, maximumCapacity)
            output = Data(count: capacity)
        }
        return nil
    }

    static func adler32(of data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Void in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var index = 0
            let count = data.count
            while index < count {
                let chunkEnd = min(index + 5552, count)
                while index < chunkEnd {
                    a &+= UInt32(base[index])
                    b &+= a
                    index += 1
                }
                a %= 65_521
                b %= 65_521
            }
        }
        return (b << 16) | a
    }
}
