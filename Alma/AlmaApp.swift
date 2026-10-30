import SwiftUI

@main
struct AlmaApp: App {
    @State private var session = SessionStore()
    @State private var wizard = WizardStore()
    @State private var store = StoreManager()
    @State private var path = NavigationPath()

    var body: some Scene {
        WindowGroup {
            Group {
                if !session.isReady {
                    // Keychain read is synchronous and fast, but showing the cream
                    // canvas rather than a flash of the signed-out screen matters on
                    // a cold launch for an already-signed-in user.
                    Theme.Palette.bg.ignoresSafeArea()
                } else if session.canUseApp {
                    NavigationStack(path: $path) {
                        UploadView(path: $path)
                            .navigationDestination(for: Route.self) { route in
                                switch route {
                                case .room: RoomView(path: $path)
                                case .mark: MarkView(path: $path)
                                case .palette: PaletteView(path: $path)
                                case .result: ResultView(path: $path)
                                case .myDesigns: MyDesignsView(path: $path)
                                case .search: SearchView()
                                }
                            }
                    }
                } else {
                    LandingView()
                }
            }
            .environment(session)
            .environment(wizard)
            .environment(store)
            .sheet(isPresented: $store.isPaywallPresented) {
                PaywallView()
                    .environment(session)
                    .environment(store)
            }
            .tint(Theme.Palette.accent)
            .task {
                session.load()
                store.startObservingTransactions(session: session)
                // Credits anything bought or renewed while the app was closed.
                if session.isSignedIn { await store.reconcile(session: session) }
                #if DEBUG
                await ScreenshotDriver.run(session: session, wizard: wizard, path: $path)
                #endif
            }
            .onChange(of: session.isSignedIn) { _, signedIn in
                if signedIn { Task { await store.reconcile(session: session) } }
            }
            .onChange(of: session.canUseApp) { _, canUse in
                // Returning to the signed-out state must not leave a half-finished
                // wizard, or the next user would inherit the previous one's photo.
                if !canUse {
                    wizard.reset()
                    path = NavigationPath()
                }
            }
        }
    }
}

/// The wizard's steps after the first. Step one is the navigation root.
enum Route: Hashable {
    case room
    case mark
    case palette
    case result
    case myDesigns
    case search
}
