import AppKit

enum EditorIconAssets {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(named name: String) -> NSImage? {
        let key = name as NSString
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: "Resources/EditorBrandIcons"
        ),
        let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = NSSize(width: 14, height: 14)
        image.isTemplate = true
        cache.setObject(image, forKey: key)
        return image
    }
}
