//
//  LibraryCategoryTabBar.swift
//  Aidoku
//
//  Created for the custom category tabs build.
//

import UIKit

/// One tab shown in the library category tab bar.
struct LibraryCategoryTabItem: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case all
        case uncategorized
        case category
        case filterGroup
    }

    let kind: Kind
    let title: String

    /// The value stored in `viewModel.currentCategory` for this item.
    var value: String? {
        switch kind {
            case .all:
                return nil
            case .uncategorized:
                return ""
            case .category, .filterGroup:
                return title
        }
    }
}

protocol LibraryCategoryTabBarDelegate: AnyObject {
    func categoryTabBar(_ tabBar: LibraryCategoryTabBar, didSelect item: LibraryCategoryTabItem)
}

/// Horizontal, browser-style tab bar for switching between library categories.
///
/// The "all" tab stays pinned on the left; the remaining tabs live in a horizontally
/// scrolling strip, so every category stays visible instead of being hidden in a menu.
final class LibraryCategoryTabBar: UICollectionReusableView {

    static let height: CGFloat = 48

    weak var delegate: LibraryCategoryTabBarDelegate?

    private(set) var items: [LibraryCategoryTabItem] = []

    private var scrollItems: [LibraryCategoryTabItem] = []

    private var selectedValue: String?
    private var lockedTitles: Set<String> = []
    private var libraryLocked = false
    private var pendingScrollToSelection = false

    // MARK: Views

    private let stripView = UIView()
    private let separatorView = UIView()
    private let allButton = TabButton()
    private let scrollView = UIScrollView()
    private let tabStackView = UIStackView()
    private var tabButtons: [TabButton] = []
    private let leftFadeView = FadeView()
    private let rightFadeView = FadeView()

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        clipsToBounds = true

        stripView.translatesAutoresizingMaskIntoConstraints = false
        stripView.backgroundColor = .secondarySystemBackground
        addSubview(stripView)

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .separator
        addSubview(separatorView)

        allButton.translatesAutoresizingMaskIntoConstraints = false
        allButton.addTarget(self, action: #selector(allButtonTapped), for: .touchUpInside)
        addSubview(allButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        addSubview(scrollView)

        tabStackView.translatesAutoresizingMaskIntoConstraints = false
        tabStackView.axis = .horizontal
        tabStackView.alignment = .fill
        tabStackView.distribution = .fill
        tabStackView.spacing = 4
        scrollView.addSubview(tabStackView)

        leftFadeView.translatesAutoresizingMaskIntoConstraints = false
        leftFadeView.isHidden = true
        addSubview(leftFadeView)

        rightFadeView.translatesAutoresizingMaskIntoConstraints = false
        rightFadeView.isHidden = true
        addSubview(rightFadeView)

        let separatorHeight = 1 / max(traitCollection.displayScale, 1)

        NSLayoutConstraint.activate([
            stripView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stripView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stripView.topAnchor.constraint(equalTo: topAnchor),
            stripView.bottomAnchor.constraint(equalTo: bottomAnchor),

            separatorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: separatorHeight),

            allButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            allButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            allButton.heightAnchor.constraint(equalToConstant: 40),

            scrollView.leadingAnchor.constraint(equalTo: allButton.trailingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 40),

            tabStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            tabStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            tabStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            tabStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            tabStackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            leftFadeView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            leftFadeView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            leftFadeView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            leftFadeView.widthAnchor.constraint(equalToConstant: 16),

            rightFadeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightFadeView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            rightFadeView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            rightFadeView.widthAnchor.constraint(equalToConstant: 44)
        ])

        updateFadeColors()
    }

    // MARK: Configuration

    func configure(
        items: [LibraryCategoryTabItem],
        selected: String?,
        lockedTitles: Set<String> = [],
        libraryLocked: Bool = false
    ) {
        self.items = items
        self.selectedValue = selected
        self.lockedTitles = lockedTitles
        self.libraryLocked = libraryLocked

        allButton.title = items.first(where: { $0.kind == .all })?.title ?? NSLocalizedString("ALL")
        allButton.showsLock = libraryLocked

        scrollItems = items.filter { $0.kind != .all }
        rebuildTabButtons()
        updateSelection(animated: false)
    }

    func updateLockState(lockedTitles titles: Set<String>, libraryLocked: Bool) {
        self.libraryLocked = libraryLocked
        allButton.showsLock = libraryLocked

        guard lockedTitles != titles, scrollItems.count == tabButtons.count else { return }
        lockedTitles = titles
        for (index, button) in tabButtons.enumerated() {
            button.showsLock = titles.contains(scrollItems[index].title)
        }
    }

    private func rebuildTabButtons() {
        for view in tabStackView.arrangedSubviews {
            tabStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        tabButtons = []

        for item in scrollItems {
            let button = TabButton()
            button.title = item.title
            button.showsLock = lockedTitles.contains(item.title)
            button.tag = tabButtons.count
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabStackView.addArrangedSubview(button)
            tabButtons.append(button)
        }

        // Keep filter groups visually separated from regular categories.
        if let firstFilterGroup = items.firstIndex(where: { $0.kind == .filterGroup }), firstFilterGroup > 1 {
            let previousTabIndex = firstFilterGroup - 2
            if tabButtons.indices.contains(previousTabIndex) {
                tabStackView.setCustomSpacing(14, after: tabButtons[previousTabIndex])
            }
        }
    }

    // MARK: Selection

    private func updateSelection(animated: Bool) {
        allButton.isTabSelected = selectedValue == nil

        for (index, button) in tabButtons.enumerated() {
            let item = scrollItems[index]
            let isSelected = item.value == selectedValue
            button.isTabSelected = isSelected
            if isSelected {
                button.accessibilityTraits.insert(.selected)
            } else {
                button.accessibilityTraits.remove(.selected)
            }
        }

        let hasSelectedItem = scrollItems.contains { $0.value == selectedValue }
        if selectedValue == nil || hasSelectedItem {
            pendingScrollToSelection = true
            setNeedsLayout()
        }

        if animated {
            UIView.animate(withDuration: 0.18) {
                self.layoutIfNeeded()
            }
        }
    }

    private func scrollToSelection(animated: Bool) {
        guard selectedValue != nil else {
            scrollView.setContentOffset(.zero, animated: animated)
            updateFades()
            return
        }
        guard let selectedIndex = tabButtons.firstIndex(where: { $0.isTabSelected }) else { return }
        scrollView.layoutIfNeeded()
        let button = tabButtons[selectedIndex]
        let buttonFrame = button.convert(button.bounds, to: tabStackView)

        let leadingFadeWidth: CGFloat = 16
        let trailingFadeWidth: CGFloat = 44
        let visibleWidth = max(
            1,
            scrollView.bounds.width - leadingFadeWidth - trailingFadeWidth
        )
        let contentWidth = tabStackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        let maxOffset = max(0, contentWidth - scrollView.bounds.width)
        var offsetX = buttonFrame.midX - leadingFadeWidth - visibleWidth / 2
        offsetX = min(max(0, offsetX), maxOffset)
        scrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: animated)
        updateFades()
    }

    // MARK: Actions

    @objc private func allButtonTapped() {
        guard let allItem = items.first(where: { $0.kind == .all }) else { return }
        select(allItem)
    }

    @objc private func tabTapped(_ sender: UIControl) {
        guard let button = sender as? TabButton, scrollItems.indices.contains(button.tag) else { return }
        select(scrollItems[button.tag])
    }

    private func select(_ item: LibraryCategoryTabItem) {
        guard item.value != selectedValue else { return }
        selectedValue = item.value
        updateSelection(animated: true)
        delegate?.categoryTabBar(self, didSelect: item)
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        updateFadeColors()
        updateFades()

        if pendingScrollToSelection, bounds.width > 0, scrollView.bounds.width > 0 {
            pendingScrollToSelection = false
            scrollToSelection(animated: false)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false {
            updateFadeColors()
            allButton.refreshAppearance()
            tabButtons.forEach { $0.refreshAppearance() }
        }
    }

    // MARK: Fades

    private func updateFadeColors() {
        let stripColor = UIColor.secondarySystemBackground.resolvedColor(with: traitCollection)
        leftFadeView.gradientColors = [stripColor, stripColor.withAlphaComponent(0)]
        rightFadeView.gradientColors = [stripColor.withAlphaComponent(0), stripColor]
    }

    private func updateFades() {
        let contentWidth = tabStackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        let maxOffset = max(0, contentWidth - scrollView.bounds.width)
        guard scrollView.bounds.width > 0 else {
            leftFadeView.isHidden = true
            rightFadeView.isHidden = true
            return
        }
        leftFadeView.isHidden = scrollView.contentOffset.x <= 1
        rightFadeView.isHidden = scrollView.contentOffset.x >= maxOffset - 1
    }
}

// MARK: - UIScrollViewDelegate

extension LibraryCategoryTabBar: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFades()
    }
}

// MARK: - Tab Button

private final class TabButton: UIControl {

    private static let horizontalPadding: CGFloat = 20
    private static let lockSpacing: CGFloat = 6
    private static let lockWidth: CGFloat = 11
    private static let maxTitleWidth: CGFloat = 180

    private let titleLabel = UILabel()
    private let lockImageView = UIImageView()
    private let contentStackView = UIStackView()

    var title: String {
        get { titleLabel.text ?? "" }
        set {
            titleLabel.text = newValue
            accessibilityLabel = newValue
            invalidateIntrinsicContentSize()
        }
    }

    var isTabSelected = false {
        didSet { updateAppearance() }
    }

    var showsLock = false {
        didSet {
            guard showsLock != oldValue else { return }
            lockImageView.isHidden = !showsLock
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let labelWidth = min(titleLabel.intrinsicContentSize.width, Self.maxTitleWidth)
        let lockWidth = showsLock ? Self.lockWidth + Self.lockSpacing : 0
        return CGSize(width: labelWidth + lockWidth + Self.horizontalPadding * 2, height: 40)
    }

    private func setUp() {
        layer.cornerRadius = 11
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.masksToBounds = true

        isAccessibilityElement = true
        accessibilityTraits = .button

        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .semibold),
            maximumPointSize: 17
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxTitleWidth).isActive = true

        lockImageView.image = UIImage(
            systemName: "lock.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        )
        lockImageView.tintColor = .tertiaryLabel
        lockImageView.contentMode = .scaleAspectFit
        lockImageView.isHidden = true
        lockImageView.translatesAutoresizingMaskIntoConstraints = false
        let lockWidthConstraint = lockImageView.widthAnchor.constraint(equalToConstant: Self.lockWidth)
        let lockHeightConstraint = lockImageView.heightAnchor.constraint(equalToConstant: Self.lockWidth)
        // UIStackView collapses hidden arranged subviews with a required 0-size constraint,
        // so these need to be sub-required to avoid Auto Layout conflicts while hidden.
        lockWidthConstraint.priority = UILayoutPriority(999)
        lockHeightConstraint.priority = UILayoutPriority(999)
        lockWidthConstraint.isActive = true
        lockHeightConstraint.isActive = true

        contentStackView.axis = .horizontal
        contentStackView.alignment = .center
        contentStackView.spacing = Self.lockSpacing
        contentStackView.isUserInteractionEnabled = false
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(lockImageView)
        contentStackView.addArrangedSubview(titleLabel)

        addSubview(contentStackView)

        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            contentStackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    override var isHighlighted: Bool {
        didSet {
            titleLabel.alpha = isHighlighted ? 0.55 : 1
        }
    }

    func refreshAppearance() {
        updateAppearance()
    }

    private func updateAppearance() {
        backgroundColor = isTabSelected ? .systemBackground : .clear
        titleLabel.textColor = isTabSelected ? .label : .secondaryLabel
        if isTabSelected {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }
    }
}

// MARK: - Fade View

private final class FadeView: UIView {

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    var gradientColors: [UIColor] = [] {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let gradientLayer = layer as? CAGradientLayer else { return }
        gradientLayer.frame = bounds
        gradientLayer.colors = gradientColors.map { $0.cgColor as Any }
        gradientLayer.locations = [NSNumber(value: 0), NSNumber(value: 1)]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
    }
}
