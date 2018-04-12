<h2>Redi/S - RedisServer Module
  <img src="redi-s-logo-286x100.png"
       align="right" width="286" height="100" />
</h2>

RedisServer is a regular Swift package. You can import and run the server
as part of your own application process.
Or write custom frontends for it.

## Using Swift Package Manager

```swift
// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "MyRedisServer",
    dependencies: [
        .package(url: "https://github.com/NozeIO/redi-s.git", 
                 from: "0.5.0")
    ],
    targets: [
        .target(name: "MyRedisServer",
                dependencies: [ "RedisServer" ])
    ]
)
```

## Start Server

The server can be configured by passing in a `Configuration` object,
but the trivial server looks like this:

```swift
import RedisServer

let server = RedisServer()
server.listenAndWait()
```

Also checkout our [redi-s example frontend](../redi-s/README.md).


### Who

Brought to you by
[ZeeZide](http://zeezide.de).
We like
[feedback](https://twitter.com/ar_institute),
GitHub stars,
cool [contract work](http://zeezide.com/en/services/services.html),
presumably any form of praise you can think of.
