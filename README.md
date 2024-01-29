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

There is a [list of supported commands](Sources/RedisServer/Commands.md).

Contributions welcome!! A lot of the missing stuff is really easy to add!


## Performance

Performance differs, e.g. lists are implemented using arrays (hence RPUSH is
okayish, LPUSH is very slow).
But looking at just the simple GET/SET, it is surprisingly close to the
highly optimized C implementation.

### 2024-01-30 Swift 5.9.2

Redi/S (1 NIO thread on M1 Mac Mini):
```
helge@M1ni ~ $ redis-benchmark -p 1337 -t SET,GET,RPUSH,INCR -n 500000 -q
WARNING: Could not fetch server CONFIG
SET: 163345.31 requests per second, p50=0.255 msec                    
GET: 167336.02 requests per second, p50=0.239 msec                    
INCR: 158780.56 requests per second, p50=0.239 msec                    
RPUSH: 157480.31 requests per second, p50=0.271 msec                    
```

Note that more threads end up being worse. Not entirely sure why.

### Those Are Older Numbers from 2018

- using Swift 4.2 on Intel, IIRC

Redi/S (2 NIO threads on MacPro 3,7 GHz Quad-Core Intel Xeon E5):
```
helge@ZeaPro ~ $ redis-benchmark -p 1337 -t SET,GET,RPUSH,INCR -n 500000 -q
SET: 48003.07 requests per second
GET: 48459.00 requests per second
INCR: 43890.45 requests per second
RPUSH: 46087.20 requests per second
```

Redis 4.0.8  (same MacPro 3,7 GHz Quad-Core Intel Xeon E5):
```
helge@ZeaPro ~ $ redis-benchmark -t SET,GET,RPUSH,INCR -n 500000 -q
SET: 54884.74 requests per second
GET: 54442.51 requests per second
INCR: 54692.62 requests per second
RPUSH: 54013.18 requests per second
```

Redi/S on RaspberryPi 3B+
```
$ redis-benchmark -h zpi3b.local -p 1337 -t SET,GET,RPUSH,INCR -n 50000 -q
SET: 4119.29 requests per second
GET: 5056.12 requests per second
INCR: 3882.59 requests per second
RPUSH: 3872.07 requests per second
```

There are [Performance notes](Sources/RedisServer/Performance.md),
looking at the specific NIO implementation of Redi/S.

Persistence is really inefficient,
the databases are just dumped as JSON via Codable.
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


## Playing with the Server

You'd like to play with this, but never used Redis before?
OK, a small tutorial on what you can do with it.

First make sure the server runs in one shell:
```
$ swift build -c release
$ .build/release/redi-s
83904:M 12 Apr 16:33:15.159 # sSZSsSZSsSZSs Redi/S is starting sSZSsSZSsSZSs
83904:M 12 Apr 16:33:15.169 # Redi/S bits=64, pid=83904, just started
83904:M 12 Apr 16:33:15.170 # Configuration loaded
 ____          _ _    ______
 |  _ \ ___  __| (_)  / / ___|    Redi/S 64 bit
 | |_) / _ \/ _` | | / /\___ \
 |  _ <  __/ (_| | |/ /  ___) |   Port: 1337
 |_| \_\___|\__,_|_/_/  |____/    PID: 83904

83904:M 12 Apr 16:33:15.176 # Server initialized
83904:M 12 Apr 16:33:15.178 * Ready to accept connections
```

Notice how the server says: "Port 1337". This is the port the server is running
on.

### Via telnet/netcat

You can directly connect to the server and issue Redis commands (the server
is then running the connection in `telnet mode`, which is different to the
regular RESP protocol):

```
$ nc localhost 1337
KEYS *
*0
SET theanswer 42
+OK
GET theanswer
$2
42
```

Redis is a key/value store. That is, it acts like a big Dictionary that
can be modified from multiple processes. Above we list the available
`KEYS`, then we set the key `theanswer` to the value 42, and retrieve it.
(Redis provides [great documentation](https://redis.io/commands)
 on the available commands, Redi/S implements many, but not all of them).

### Via redis-cli

Redis provides a tool called `redis-cli`, which is a much more convenient
way to access the server.
On macOS you can install that using `brew install redis` (which also gives
you the real server),
on Ubuntu you can grab it via `sudo apt-get install redis-tools`.

The same thing we did in `telnet` above:

```
$ redis-cli -p 1337
127.0.0.1:1337> KEYS *
1) "theanswer"
127.0.0.1:1337> SET theanswer 42
OK
127.0.0.1:1337> GET theanswer
"42"
```

### Key Expiration

Redis is particularily useful for HTTP session stores, and for caches.
When setting a key, you can set an "expiration" (in seconds, milliseconds,
or Unix timestamps):

```
127.0.0.1:1337> EXPIRE theanswer 10
(integer) 1
127.0.0.1:1337> TTL theanswer
(integer) 6
127.0.0.1:1337> GET theanswer
"42"
127.0.0.1:1337> TTL theanswer
(integer) -2
127.0.0.1:1337> GET theanswer
(nil)
```

We are using "strings" here. In Redis "strings" are actually "Data" objects,
i.e. binary arrays of bytes (this is even true for bytes!).
For example in a web application, you could use the "session-id" you generate,
serialize your session into a Data object, and then store it like
`SET session-id <session> TTL 600`.
  
### Key Generation

But how do we generate keys (e.g. session-ids) in a distributed setting?
As usual there are many ways to do this.
For example you could use a Redis integer key which provides atomic increment
and decrement operations:

```
127.0.0.1:1337> SET idsequence 0
OK
127.0.0.1:1337> INCR idsequence
(integer) 1
127.0.0.1:1337> INCR idsequence
(integer) 2
```

Or if you generate keys on the client side, you can validate that they are
unique using [SETNX](https://redis.io/commands/setnx). For example:

```
127.0.0.1:1337> SETNX mykey 10
(integer) 1
```

And another client will get

```
127.0.0.1:1337> SETNX mykey 10
(integer) 0
```

### Simple Lists

Redis cannot only store string (read: Data) values, it can also store
lists, sets and hashes (dictionaries).
As well as some other datatypes:
[Data Types Intro](https://redis.io/topics/data-types-intro).

```
127.0.0.1:1337> RPUSH chatchannel "Hi guys!"
(integer) 1
127.0.0.1:1337> RPUSH chatchannel "How is it going?"
(integer) 2
127.0.0.1:1337> LLEN chatchannel
(integer) 2
127.0.0.1:1337> LRANGE chatchannel 0 -1
1) "Hi guys!"
2) "How is it going?"
127.0.0.1:1337> RPOP chatchannel
"How is it going?"
127.0.0.1:1337> RPOP chatchannel
"Hi guys!"
127.0.0.1:1337> RPOP chatchannel
(nil)
```

### Monitoring

Assume you want to debug what's going on on your Redis server.
You can do this by connecting w/ a fresh client and put that into
"monitoring" mode. The Redis server will echo all commands it receives
to that monitor:

```
$ redis-cli -p 1337
127.0.0.1:1337> MONITOR
OK
```

Some other client:

```
127.0.0.1:1337> hmset user:1000 username antirez birthyear 1976 verified 1
OK
127.0.0.1:1337> hmget user:1000 username verified
1) "antirez"
2) "1"
```

The monitor will print:

```
1523545069.071390 [0 127.0.0.1:60904] "hmset" "user:1000" "username" "antirez" "birthyear" "1976" "verified" "1"
1523545087.016070 [0 127.0.0.1:60904] "hmget" "user:1000" "username" "verified"
```

### Publish/Subscribe

Redis includes a simple publish/subscribe server.
Any numbers of clients can subscribe to any numbers of channels.
Other clients can then push "messages" to a channel, and all
subscribed clients will receive them.

One client:
```
127.0.0.1:1337> PSUBSCRIBE thermostats*
Reading messages... (press Ctrl-C to quit)
1) psubscribe
2) "thermostats*"
3) (integer) 1
```

Another client (the reply contains the number of consumers):

```
127.0.0.1:1337> PUBLISH thermostats:kitchen "temperature set to 42℃"
(integer) 1
```

The subscribed client will get:
```
1) message
2) "thermostats:kitchen"
3) "temperatur set to 4242℃"
```

> Note: PubSub is separate to the key-value store. You cannot watch keys using
> that! (there are blocking list operations for producer/consumer scenarios,
> but those are not yet supported by Redi/S)


### Benchmarking

Redis tools also include a tool called `redis-benchmark` which can be,
similar to `apache-bench` or `wrk` be used to measure the server performance.

For example, to exercise the server with half a million SET, GET, RPUSH and INCR
requests each:

```
$ redis-benchmark -p 1337 -t SET,GET,RPUSH,INCR -n 500000 -q
SET: 43192.81 requests per second
GET: 46253.47 requests per second
INCR: 38952.95 requests per second
RPUSH: 39305.09 requests per second
```


## Who

Brought to you by
[ZeeZide](http://zeezide.de).
We like
[feedback](https://twitter.com/ar_institute),
GitHub stars,
cool [contract work](http://zeezide.com/en/services/services.html),
presumably any form of praise you can think of.

There is a `#swift-nio` channel on the
[swift-server Slack](https://t.co/W1vfsb9JAB).
