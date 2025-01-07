import SwiftUI

struct FlowLayout: View {
    var spacing: CGFloat
    var content: [AnyView]
    
    init<Data: RandomAccessCollection, Content: View>(
        spacing: CGFloat = 8,
        data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.spacing = spacing
        self.content = data.map { AnyView(content($0)) }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(0..<content.count, id: \.self) { index in
                        content[index]
                    }
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
                TagView(tag: tag)
            }
        )
        .padding()
    }
}
#endif 