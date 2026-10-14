import Foundation
import UIKit

// MARK: - 阅读位置

/// 全书坐标 = 章节下标 + 章节内页码
struct ReaderLocation: Equatable, Hashable {
    var chapter: Int
    var page: Int

    static let zero = ReaderLocation(chapter: 0, page: 0)
}

// MARK: - 分页引擎

/// 基于 CoreText 的分页。只关心排版相关属性（字体/行距/段距/页边距/页面尺寸），
/// 颜色不参与排版，所以换主题不需要重新分页。
enum PaginationEngine {
    static func pageRanges(
        text: NSAttributedString,
        pageSize: CGSize,
        insets: UIEdgeInsets
    ) -> [NSRange] {
        let contentWidth = pageSize.width - insets.left - insets.right
        let contentHeight = pageSize.height - insets.top - insets.bottom
        guard contentWidth > 12, contentHeight > 12, text.length > 0 else { return [] }

        let rect = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        let path = CGPath(rect: rect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)

        var ranges: [NSRange] = []
        ranges.reserveCapacity(max(4, text.length / 800))
        var location = 0
        let total = text.length
        var safetyCounter = 0

        while location < total {
            safetyCounter += 1
            if safetyCounter > 20_000 { break }

            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            let length = Int(visible.length)

            if length <= 0 {
                // 一页放不下任何内容（异常小的字号/页面），强制推进避免死循环
                let remaining = total - location
                ranges.append(NSRange(location: location, length: min(remaining, 1)))
                location += 1
                continue
            }

            ranges.append(NSRange(location: location, length: length))
            location += length
        }

        return ranges
    }

    static func pageContaining(
        characterOffset: Int,
        ranges: [NSRange]
    ) -> Int {
        guard !ranges.isEmpty else { return 0 }
        let target = max(0, min(characterOffset, ranges.reduce(0) { max($0, $1.location + $1.length) } - 1))
        for (index, range) in ranges.enumerated() {
            if target >= range.location, target < range.location + range.length {
                return index
            }
        }
        return ranges.count - 1
    }

    static func characterOffset(
        pageIndex: Int,
        ranges: [NSRange]
    ) -> Int {
        guard ranges.indices.contains(pageIndex) else { return 0 }
        return ranges[pageIndex].location
    }
}
