import SwiftUI
import UniformTypeIdentifiers

/// The file shelf: park files, drag them out, AirDrop them, open or remove them.
struct ShelfView: View {
    @EnvironmentObject private var shelf: ShelfManager
    @State private var isTargeted = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                CardTitle("Raf · \(shelf.items.count) öğe", symbol: "tray.full.fill")
                Spacer()
                if !shelf.items.isEmpty {
                    Button {
                        shelf.airDropAll()
                    } label: {
                        Label("Tümünü AirDrop'la", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    // Raf kopyaları tek nüsha olabilir — onaysız toplu silme veri kaybettirir.
                    ConfirmingButton(title: "Temizle", systemImage: "trash") {
                        shelf.removeAll()
                    }
                }
            }
            if shelf.items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(isTargeted ? Color.orange : .white.opacity(0.2))
                    Text("Dosyaları çentiğe sürükleyip bırakın")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Buradan tekrar dışarı sürükleyebilir veya AirDrop'layabilirsiniz")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfItemView(item: item)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 2)
                    .animation(Motion.standard, value: shelf.items.count)
                }
            }
        }
        .islandCard()
        .onDrop(of: [UTType.fileURL, UTType.image, UTType.plainText], isTargeted: $isTargeted) { providers in
            shelf.handle(providers: providers)
        }
    }
}

struct ShelfItemView: View {
    @EnvironmentObject private var shelf: ShelfManager
    let item: ShelfItem
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: shelf.icon(for: item))
                .resizable()
                .frame(width: 40, height: 40)
            Text(item.fileName)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.1 : 0.05))
        )
        .overlay(alignment: .topTrailing) {
            // Hover'da çift-tıkla-aç ipucu (aksi halde keşfedilemez).
            if hovering {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(4)
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .onDrag {
            NSItemProvider(contentsOf: item.storedURL) ?? NSItemProvider()
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(item.storedURL)
        }
        .contextMenu {
            Button("Aç") { NSWorkspace.shared.open(item.storedURL) }
            Button("AirDrop ile Paylaş") { shelf.airDrop(item) }
            Button("Finder'da Göster") { shelf.revealInFinder(item) }
            Divider()
            Button("Raftan Kaldır") { shelf.remove(item) }
        }
        .help("Çift tıkla aç · dışarı sürükleyerek istediğin yere bırak")
    }
}
