import SwiftUI
import UIKit

// MARK: - 点击分区

enum ReaderTapZone {
    case leading
    case trailing
    case center
}

// MARK: - 单页渲染视图

/// 用 CoreText 直接绘制一页内容。前景色由主题提供，排版字符串里不带颜色。
final class TextPageView: UIView {
    var chapterText: NSAttributedString?
    var pageRange: NSRange = NSRange(location: 0, length: 0)
    var theme: ReaderTheme = .default { didSet { setNeedsDisplay() } }
    var insets: UIEdgeInsets = .zero { didSet { setNeedsDisplay() } }
    var chapterTitle: String = ""
    var pageIndex: Int = 0
    var pageTotal: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        theme.uiBackground.setFill()
        context.fill(bounds)

        if let text = chapterText, text.length > 0 {
            context.saveGState()
            let contentRect = bounds.inset(by: insets)
            if contentRect.width > 8, contentRect.height > 8 {
                context.textMatrix = .identity
                context.translateBy(x: 0, y: bounds.height)
                context.scaleBy(x: 1, y: -1)

                let path = CGPath(rect: contentRect, transform: nil)
                let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: pageRange.location, length: 0),
                    path,
                    nil
                )
                theme.uiText.setFill()
                CTFrameDraw(frame, context)
            }
            context.restoreGState()
        }

        drawFooter()
    }

    private func drawFooter() {
        guard bounds.height > 60 else { return }
        let footerFont = UIFont.systemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: theme.uiSecondary,
        ]
        let footerTop = bounds.maxY - 26

        if !chapterTitle.isEmpty {
            (chapterTitle as NSString).draw(
                with: CGRect(x: insets.left, y: footerTop, width: bounds.width * 0.55, height: 18),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attributes,
                context: nil
            )
        }
        if pageTotal > 0 {
            let text = "\(pageIndex) / \(pageTotal)"
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: CGPoint(x: bounds.maxX - insets.right - size.width, y: footerTop),
                withAttributes: attributes
            )
        }
    }
}

// MARK: - 单页控制器

final class TextPageViewController: UIViewController {
    let location: ReaderLocation
    private weak var engine: ReaderEngine?
    private var theme: ReaderTheme
    private var insets: UIEdgeInsets

    private var pageView: TextPageView {
        view as! TextPageView
    }

    init(location: ReaderLocation, engine: ReaderEngine?, theme: ReaderTheme, insets: UIEdgeInsets) {
        self.location = location
        self.engine = engine
        self.theme = theme
        self.insets = insets
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let pageView = TextPageView()
        pageView.theme = theme
        pageView.insets = insets
        view = pageView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
    }

    func update(theme: ReaderTheme, insets: UIEdgeInsets) {
        self.theme = theme
        self.insets = insets
        render()
    }

    func render() {
        guard let engine = engine else { return }
        let ranges = engine.ranges(forChapter: location.chapter)

        pageView.theme = theme
        pageView.insets = insets
        pageView.chapterTitle = engine.chapterTitle(at: location.chapter)
        pageView.pageIndex = location.page + 1
        pageView.pageTotal = ranges.count

        if ranges.indices.contains(location.page) {
            pageView.chapterText = engine.attributedString(chapter: location.chapter)
            pageView.pageRange = ranges[location.page]
        } else {
            pageView.chapterText = nil
            pageView.pageRange = NSRange(location: 0, length: 0)
        }
        pageView.setNeedsDisplay()
    }
}

// MARK: - 翻页容器

final class ReaderPagerController: UIPageViewController,
    UIPageViewControllerDataSource,
    UIPageViewControllerDelegate {

    private var engine: ReaderEngine?
    private var theme: ReaderTheme = .default
    private var insets: UIEdgeInsets = .zero
    private(set) var current: ReaderLocation = .zero

    weak var viewModel: ReaderViewModel?

    override init(
        transitionStyle style: UIPageViewController.TransitionStyle,
        navigationOrientation: UIPageViewController.NavigationOrientation,
        options: [UIPageViewController.OptionsKey: Any]? = nil
    ) {
        super.init(transitionStyle: style, navigationOrientation: navigationOrientation, options: options)
        dataSource = self
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.uiBackground
        setupTapHandling()
    }

    func configure(
        engine: ReaderEngine,
        theme: ReaderTheme,
        insets: UIEdgeInsets,
        initial: ReaderLocation
    ) {
        self.engine = engine
        self.theme = theme
        self.insets = insets
        current = initial
        view.backgroundColor = theme.uiBackground
        setViewControllers([makePage(for: initial)], direction: .forward, animated: false)
    }

    func applyTheme(_ newTheme: ReaderTheme, insets newInsets: UIEdgeInsets) {
        theme = newTheme
        insets = newInsets
        view.backgroundColor = newTheme.uiBackground
        viewControllers?.forEach {
            ($0 as? TextPageViewController)?.update(theme: newTheme, insets: newInsets)
        }
    }

    func refreshVisiblePages() {
        viewControllers?.forEach {
            ($0 as? TextPageViewController)?.render()
        }
    }

    func scrollTo(_ target: ReaderLocation, animated: Bool) {
        guard target != current, engine != nil else { return }
        let score = { (location: ReaderLocation) in location.chapter * 1_000_000 + location.page }
        let direction: UIPageViewController.NavigationDirection =
            score(target) > score(current) ? .forward : .reverse
        current = target
        setViewControllers([makePage(for: target)], direction: direction, animated: animated)
        viewModel?.didPageTurn(to: target)
    }

    // MARK: - 数据源

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let pageVC = viewController as? TextPageViewController,
              let previous = previousLocation(from: pageVC.location) else { return nil }
        return makePage(for: previous)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let pageVC = viewController as? TextPageViewController,
              let next = nextLocation(from: pageVC.location) else { return nil }
        return makePage(for: next)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed else { return }
        guard let visible = viewControllers?.first as? TextPageViewController else { return }
        guard visible.location != current else { return }
        current = visible.location
        Haptics.selection()
        viewModel?.didPageTurn(to: current)
    }

    // MARK: - 私有
    private func makePage(for location: ReaderLocation) -> TextPageViewController {
        TextPageViewController(location: location, engine: engine, theme: theme, insets: insets)
    }

    private func nextLocation(from location: ReaderLocation) -> ReaderLocation? {
        engine?.nextLocation(from: location)
    }

    private func previousLocation(from location: ReaderLocation) -> ReaderLocation? {
        engine?.previousLocation(from: location)
    }

    private func setupTapHandling() {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesEnded = false
        view.addGestureRecognizer(recognizer)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let point = recognizer.location(in: view)
        let width = max(view.bounds.width, 1)
        let zone: ReaderTapZone
        if point.x < width * 0.3 {
            zone = .leading
        } else if point.x > width * 0.7 {
            zone = .trailing
        } else {
            zone = .center
        }
        viewModel?.handleTap(zone)
    }
}

// MARK: - SwiftUI 桥接

struct ReaderPagerView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: ReaderViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> ReaderPagerController {
        let controller = ReaderPagerController(
            transitionStyle: viewModel.settings.pageAnimation.uiTransitionStyle,
            navigationOrientation: .horizontal
        )
        context.coordinator.controller = controller
        controller.viewModel = viewModel
        controller.configure(
            engine: viewModel.engine,
            theme: viewModel.resolvedTheme,
            insets: viewModel.settings.textInsets,
            initial: viewModel.location
        )
        context.coordinator.lastTheme = viewModel.resolvedTheme
        context.coordinator.lastInsets = viewModel.settings.textInsets
        return controller
    }

    func updateUIViewController(_ controller: ReaderPagerController, context: Context) {
        let theme = viewModel.resolvedTheme
        let insets = viewModel.settings.textInsets
        if context.coordinator.lastTheme != theme || context.coordinator.lastInsets != insets {
            context.coordinator.lastTheme = theme
            context.coordinator.lastInsets = insets
            controller.applyTheme(theme, insets: insets)
        }

        if let target = viewModel.pendingJump {
            DispatchQueue.main.async {
                viewModel.pendingJump = nil
                controller.scrollTo(target, animated: false)
            }
        }
    }

    final class Coordinator {
        let viewModel: ReaderViewModel
        weak var controller: ReaderPagerController?
        var lastTheme: ReaderTheme?
        var lastInsets: UIEdgeInsets?

        init(viewModel: ReaderViewModel) {
            self.viewModel = viewModel
        }
    }
}
