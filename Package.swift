// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "redi-s",
    products: [
        .library   (name: "RedisServer", targets: [ "RedisServer"  ]),
        .executable(name: "redi-s",      targets: [ "redi-s" ]),
    ],
    dependencies: [
        .package(url: "https://github.com/NozeIO/swift-nio-redis.git", 
                 from: "0.8.3")
    ],
    targets: [
        .target(name: "RedisServer", dependencies: [ "NIORedis"    ]),
        .target(name: "redi-s",      dependencies: [ "RedisServer" ])
    ]
)
