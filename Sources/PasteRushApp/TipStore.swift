#if PASTERUSH_APP_STORE
import AppKit
import PasteRushCore
import StoreKit
import SwiftUI

enum TipProductID {
    static let all = [
        "com.itszymczak.pasterush.tip.small",
        "com.itszymczak.pasterush.tip.medium",
        "com.itszymczak.pasterush.tip.large",
    ]
}

@MainActor
final class TipStore: ObservableObject {
    static let shared = TipStore()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasing = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    private init() {}

    func start() {
        guard updates == nil else { return }
        updates = Task { await observeTransactions() }
        Task { await load() }
    }

    func load() async {
        do {
            let loaded = try await Product.products(for: TipProductID.all)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            products = []
        }
    }

    func purchase(_ product: Product) async {
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                message = L10n.tr("tip.thanks")
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func observeTransactions() async {
        for await update in Transaction.updates {
            guard let transaction = try? verified(update) else { continue }
            await transaction.finish()
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw TipStoreError.unverified
        case .verified(let value):
            return value
        }
    }
}

enum TipStoreError: Error {
    case unverified
}

@MainActor
enum TipPresenter {
    static func show() {
        TipStore.shared.start()
        TipSupportWindowController.shared.show()
    }
}

@MainActor
final class TipSupportWindowController: NSWindowController {
    static let shared = TipSupportWindowController()

    private init() {
        let hosting = NSHostingController(rootView: TipSupportView())
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.tr("tip.title")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 440, height: 250))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct TipSupportView: View {
    @ObservedObject private var store = TipStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("tip.title"))
                .font(.title2.bold())
            Text(L10n.tr("tip.body"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.products.isEmpty {
                Text(L10n.tr("tip.unavailable"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.products, id: \.id) { product in
                    Button(product.displayName + " · " + product.displayPrice) {
                        Task { await store.purchase(product) }
                    }
                    .disabled(store.purchasing)
                    .buttonStyle(.borderedProminent)
                }
            }
            if let message = store.message {
                Text(message)
                    .font(.callout)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 440, alignment: .topLeading)
        .task { await store.load() }
    }
}
#endif
