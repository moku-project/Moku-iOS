import UIKit

final class CanvasScrollView: UIScrollView {
    var didLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        didLayout?()
    }
}
