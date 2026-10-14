import CoreFoundation
import Foundation

/// 文本编码探测：UTF-8 / UTF-16 / GB18030 / Big5 / Shift-JIS
/// 中文网络小说里 GBK 编码仍然常见，识别失败会变成满屏乱码，所以这里做得保守一些。
enum EncodingDetector {
    static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    static let big5 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
    )

    /// 探测编码并返回（编码, 标准名称）
    static func detect(in data: Data) -> (encoding: String.Encoding, name: String) {
        let bytes = [UInt8](data.prefix(4))

        // 1. BOM 优先
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return (.utf8, "UTF-8")
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            return (.utf16LittleEndian, "UTF-16LE")
        }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            return (.utf16BigEndian, "UTF-16BE")
        }

        // 2. 合法 UTF-8 直接采信
        if String(data: data, encoding: .utf8) != nil {
            return (.utf8, "UTF-8")
        }

        // 3. 用采样文本给候选编码打分
        let sample = data.prefix(256_000)
        let candidates: [(String.Encoding, String)] = [
            (gb18030, "GB18030"),
            (big5, "Big5"),
            (.utf16, "UTF-16"),
            (.shiftJIS, "Shift-JIS"),
        ]

        var bestEncoding = gb18030
        var bestName = "GB18030"
        var bestScore = -Double.greatestFiniteMagnitude

        for (encoding, name) in candidates {
            guard let text = String(data: sample, encoding: encoding) else { continue }
            let score = qualityScore(of: text)
            if score > bestScore {
                bestScore = score
                bestEncoding = encoding
                bestName = name
            }
        }

        return (bestEncoding, bestName)
    }

    private static func qualityScore(of text: String) -> Double {
        var cjk = 0
        var total = 0
        var replacement = 0
        for scalar in text.unicodeScalars {
            total += 1
            switch scalar.value {
            case 0xFFFD:
                replacement += 1
            case 0x3000...0x303F, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
                cjk += 1
            default:
                break
            }
        }
        guard total > 0 else { return 0 }
        let ratio = Double(cjk) / Double(total)
        let penalty = Double(replacement) / Double(total) * 3.0
        return ratio - penalty
    }

    /// 把文本按指定编码写出（导出 / 备份用）
    static func encode(_ text: String, with name: String) -> Data? {
        switch name {
        case "UTF-16LE": return text.data(using: .utf16LittleEndian)
        case "UTF-16BE": return text.data(using: .utf16BigEndian)
        case "GB18030": return text.data(using: gb18030)
        case "Big5": return text.data(using: big5)
        default: return text.data(using: .utf8)
        }
    }
}
