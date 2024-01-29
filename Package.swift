// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "redi-s",
    products: [
        .library   (name: "RedisServer", targets: [ "RedisServer"  ]),
        .executable(name: "redi-s",      targets: [ "redi-s" ]),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftNIOExtras/swift-nio-redis.git", 
                 from: "0.10.3"),
        .package(url: "https://github.com/apple/swift-atomics", from: "1.2.0")
    ],
    targets: [
        .target(name: "RedisServer", dependencies: [ "NIORedis", "Atomics" ]),
        .target(name: "redi-s",      dependencies: [ "RedisServer" ])
    ]
)
