import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            IslandView()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

/// The black island itself: notch-sized when collapsed, a full panel when expanded.
struct IslandView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var shelf: ShelfManager
    @EnvironmentObject private var prefs: Preferences

    private var shape: NotchShape {
        NotchShape(bottomRadius: vm.isExpanded ? prefs.expandedCornerRadius : 12)
    }

    private var islandWidth: CGFloat {
        vm.isExpanded ? vm.expandedSize.width : vm.collapsedPillSize.width
    }

    private var islandHeight: CGFloat {
        vm.isExpanded ? vm.expandedSize.height : vm.collapsedPillSize.height
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .overlay(
                    shape.strokeBorder(
                        Color.white.opacity(vm.isExpanded ? 0.16 : 0.07),
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: .black.opacity(vm.isExpanded ? 0.5 : 0.25),
                    radius: vm.isExpanded ? 16 : 5,
                    y: 5
                )
            Group {
                if vm.isExpanded {
                    ExpandedView()
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    CollapsedView()
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
        }
        .frame(width: islandWidth, height: islandHeight)
        .background(DebugFrameReporter())
        .contentShape(shape)
        .onTapGesture {
            vm.expand()
        }
        .onDrop(
            of: [UTType.fileURL, UTType.image, UTType.plainText],
            delegate: IslandDropDelegate(vm: vm, shelf: shelf)
        )
        .animation(prefs.expandSpring, value: vm.isExpanded)
    }
}

/// Dragging anything over the notch opens the shelf; dropping parks it there.
struct IslandDropDelegate: DropDelegate {
    let vm: NotchViewModel
    let shelf: ShelfManager

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            vm.isDragHovering = true
            vm.expand(tab: .shelf)
        }
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated {
            vm.isDragHovering = false
            // Sürükleme sırasında mouseMoved gelmez; imleç adayı sürüklemeyle
            // terk ettiği için içeride-sayma bayrağını elle düşür.
            vm.isMouseInside = false
            vm.collapse(afterDelay: 0.8)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL, UTType.image, UTType.plainText])
        return MainActor.assumeIsolated {
            vm.isDragHovering = false
            return shelf.handle(providers: providers)
        }
    }
}

/// `--debug-geometry` ile açıldığında adanın pencere içi konumunu stdout'a döker.
struct DebugFrameReporter: View {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--debug-geometry")

    var body: some View {
        if Self.enabled {
            GeometryReader { geo in
                Color.clear
                    .onAppear { report(geo) }
                    .onChange(of: geo.size) { _ in report(geo) }
            }
        }
    }

    private func report(_ geo: GeometryProxy) {
        let frame = geo.frame(in: .global)
        print("[geo:island] global=\(frame) midX=\(frame.midX)")
        fflush(stdout)
    }
}

/// Notch silhouette: flush with the screen's top edge, rounded bottom corners.
struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    var inset: CGFloat = 0

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
