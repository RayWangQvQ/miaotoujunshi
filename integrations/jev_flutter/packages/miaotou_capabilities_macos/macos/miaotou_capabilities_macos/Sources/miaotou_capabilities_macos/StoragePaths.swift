import Foundation

/// The two directories this port reads from and writes to.
///
/// Both are answers only a running application can give, and that is the whole
/// reason they are here rather than in Dart. Everything downstream — joining a
/// repository-relative key, reading bytes, encoding a store's JSON — is
/// `dart:io` and is tested against a temporary directory.
///
/// ## The resource root
///
/// `Bundle.main.resourcePath` is `.app/Contents/Resources`, which is where the
/// build phase's `rsync` puts the payload tree. Nothing in Dart could have found
/// it: a packaged app has no repository above it, and the path does not exist
/// until AppKit has laid the bundle out.
///
/// ## The container
///
/// `NSApplicationSupportDirectory` inside the app's own sandbox container. Not
/// `~/Library/Application Support` by hand and not the upstream script's
/// `goutoujunshi` folder: under the sandbox the home directory is **not
/// writable**, and a hard-coded path is either wrong on somebody's machine or a
/// second place to change when it moves. This is the location the system
/// documents for exactly this use.
///
/// The three stores each own one file in it. Creating the directory is left to
/// Dart, so that "make the directory this app writes into" stays a branch a test
/// can reach; this only reports where it is.
enum StoragePaths {
    /// `com.miaotoujunshi.miaotouApp` — the application's own bundle identifier.
    ///
    /// Used as the container subdirectory so the stores cannot collide with
    /// another application's, and so the whole of this app's local state is one
    /// removable directory. The upstream Python store used
    /// `…/Application Support/goutoujunshi`; it is a different product's
    /// directory and this port does not read it (see `secrets.dart` for why the
    /// keychain half is likewise not shared).
    static let directoryName = "com.miaotoujunshi.miaotouApp"

    /// `.app/Contents/Resources`, or nil if the bundle reports no resource path.
    ///
    /// Nil rather than a substituted directory: a payload read that silently
    /// found some other tree would be a read of files the app does not ship,
    /// which is the one thing ADR-0008 exists to prevent.
    static func resourceRoot() -> String? {
        Bundle.main.resourcePath
    }

    /// The one directory this app may write.
    static func containerDirectory() throws -> String {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(directoryName, isDirectory: true).path
    }
}

/// What [StoragePaths] refused, in a form the channel can carry.
enum StoragePathError: Error {
    case noResourceRoot
    case noContainerDirectory(String)

    var code: Int {
        switch self {
        case .noResourceRoot:
            return 1
        case .noContainerDirectory:
            return 2
        }
    }

    var message: String {
        switch self {
        case .noResourceRoot:
            return "读不出应用程序包的资源目录，共享载荷无法定位"
        case .noContainerDirectory(let detail):
            return "读不出可写的应用数据目录：\(detail)"
        }
    }
}
