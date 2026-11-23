import SwiftUI

struct PatchProjectsView: View {
    @EnvironmentObject private var store: PatchProjectStore
    @State private var showImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("NO PATCHES INSTALLED")
                            .font(.system(.headline, design: .monospaced))

                        Text("Nhấn nút '+' để thêm gói patch (.OGIOS)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.packageURL.lastPathComponent)
                                    .font(.system(.body, design: .monospaced).bold())

                                if let project = item.project {
                                    Text(project.name)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                store.delete(store.items[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Patch Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }

                    store.importPackage(at: url)

                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}
