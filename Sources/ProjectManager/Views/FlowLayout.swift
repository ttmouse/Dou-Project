import SwiftUI

struct FlowLayout: View {
    let spacing: CGFloat
    let data: [String]
    let content: (String) -> AnyView
    
    init<Content: View>(
        spacing: CGFloat = 8,
        data: [String],
        @ViewBuilder content: @escaping (String) -> Content
    ) {
        self.spacing = spacing
        self.data = data
        self.content = { AnyView(content($0)) }
    }
    
    var body: some View {
        GeometryReader { geometry in
            self.generateContent(in: geometry)
        }
    }
    
    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        var lastHeight = CGFloat.zero
        
        return ZStack(alignment: .topLeading) {
            ForEach(Array(data.enumerated()), id: \.element) { _, item in
                content(item)
                    .padding(.horizontal, 4)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > geometry.size.width {
                            width = 0
                            height -= lastHeight
                        }
                        let result = width
                        if item == data.last {
                            width = 0
                        } else {
                            width -= dimension.width
                            width -= spacing
                        }
                        lastHeight = dimension.height
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == data.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
    }
}

#if DEBUG
struct FlowLayout_Previews: PreviewProvider {
    static var previews: some View {
        FlowLayout(
            spacing: 8,
            data: ["SwiftUI", "macOS", "Swift", "Xcode", "VSCode"],
            content: { tag in
                TagView(tag: tag, color: .blue, fontSize: 13)
            }
        )
        .padding()
    }
}
#endif 