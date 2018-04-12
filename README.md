<h2>Redi/S
  <img src="http://zeezide.com/img/redi-s-logo-286x100.png"
       align="right" width="286" height="100" />
</h2>

![Swift4](https://img.shields.io/badge/swift-4-blue.svg)
![macOS](https://img.shields.io/badge/os-macOS-green.svg?style=flat)
![tuxOS](https://img.shields.io/badge/os-tuxOS-green.svg?style=flat)
![Travis](https://travis-ci.org/NozeIO/redi-s.svg?branch=develop)

Redi/S is a **Redis server implementation** in the
[Swift](https://swift.org)
programming language.
Based on Apple's 
[SwiftNIO](https://github.com/apple/swift-nio)
framework.

What is [Redis](https://redis.io)? Checkout the home page,
but it is an easy to use and very popular Key-Value Store,
w/ PubSub functionality.

It is not meant to replace the C based [Redis](https://redis.io) server,
but the goal is to make it feature complete and well performing.

Use cases:

- Testing of server apps (pull up a Redi/S within your Xcode just for testing).
- As an "embedded" database. Redi/S comes as a regular Swift package you can
  directly embed into your own server or application.
- Easy to extend in a safy language.


## Supported Commands

Redi/S supports a lot, including PubSub and monitoring.<br />
Redi/S supports a lot *not*, including transactions or HyperLogLogs.

There is a [list of supported commands](Commands.md).

Contributions welcome!! A lot of the missing stuff is really easy to add!


## Performance

Performance differs, e.g. lists are implemented using arrays (hence RPUSH is
okayish, LPUSH is very slow).
But looking at just the simple GET/SET, it is surprisingly close to the
highly optimized C implementation:

Redi/S (2 NIO threads on 3,7 GHz Quad-Core Intel Xeon E5):
```
helge@ZeaPro ~ $ redis-benchmark -p 1337 -t SET,GET,RPUSH,INCR -n 500000 -q
SET: 46412.33 requests per second
GET: 47393.36 requests per second
INCR: 37094.74 requests per second
RPUSH: 41872.54 requests per second
```

Redis 4.0.8  (same 4-Core MacPro):
```
helge@ZeaPro ~ $ redis-benchmark -t SET,GET,RPUSH,INCR -n 500000 -q
SET: 54884.74 requests per second
GET: 54442.51 requests per second
INCR: 54692.62 requests per second
RPUSH: 54013.18 requests per second
```

There are [Performance notes](Sources/RedisServer/Performance.md),
looking at the specific NIO implementation of Redi/S.

Persistence is really inefficient,
the databases are just dump as JSON via Codable.
Easy to fix.


## How to run

```
$ swift build -c release
$ .build/release/redi-s
2383:M 11 Apr 17:04:16.296 # sSZSsSZSsSZSs Redi/S is starting sSZSsSZSsSZSs
2383:M 11 Apr 17:04:16.302 # Redi/S bits=64, pid=2383, just started
2383:M 11 Apr 17:04:16.303 # Configuration loaded
 ____          _ _    ______
 |  _ \ ___  __| (_)  / / ___|    Redi/S 64 bit
 | |_) / _ \/ _` | | / /\___ \
 |  _ <  __/ (_| | |/ /  ___) |   Port: 1337
 |_| \_\___|\__,_|_/_/  |____/    PID: 2383

2383:M 11 Apr 17:04:16.304 # Server initialized
2383:M 11 Apr 17:04:16.305 * Ready to accept connections
```

## Status

There are a few inefficiencies, the worst being the persistent storage.
Yet generally this seems to work fine.

The implementation has grown a bit and could use a little refactoring,
specially the database dump parts.


### Who

Brought to you by
[ZeeZide](http://zeezide.de).
We like
[feedback](https://twitter.com/ar_institute),
GitHub stars,
cool [contract work](http://zeezide.com/en/services/services.html),
presumably any form of praise you can think of.

There is a `#swift-nio` channel on the
[swift-server Slack](https://t.co/W1vfsb9JAB).
