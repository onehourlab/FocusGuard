// swift-tools-version:5.9
import PackageDescription

// アプリ本体と各拡張（Shield・監視・レポート）が共通で使う、UIに依存しないロジック。
// 審査ルール・目的の類似判定・集計はここにあり、Mac では `swift test` だけで単体テストできる。
let package = Package(
    name: "FocusGuardKit",
    defaultLocalization: "ja",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FocusGuardKit", targets: ["FocusGuardKit"])
    ],
    targets: [
        .target(name: "FocusGuardKit"),
        .testTarget(name: "FocusGuardKitTests", dependencies: ["FocusGuardKit"])
    ]
)
