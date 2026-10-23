import Foundation

extension Project {
    var displayPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
