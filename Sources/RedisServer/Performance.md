# Redi/S - Performance

Questions on any of that?
Either Twitter [@helje5](https://twitter.com/helje5),
or join the `#swift-nio` channel on the
[swift-server Slack](https://t.co/W1vfsb9JAB).


## Todos

There are still a few things which could be easily optimized a lot regardless of
bigger architectural changes:

- integer backed store for strings (INCR/DECR)
- do proper in-place modifications for sets


## Copy on Write

The current implementation is based around Swift's value types.
The idea is/was to make heavy use of the Copy-on-Write features and thereby
unblock the database thread as quickly as possible.

For example if we deliver a result, we only grab the result in the locked DB context,
all the rendering and socket delivery is happening in a NIO eventloop thread.

The same goes for persistence. We can grab the current value of the database
dictionary and persist that, w/o any extra locking
(though C Redis is much more efficient w/ the fork approach ...)

> There is another flaw here. The "copy" will happen in the database scope,
> which obviously is sub-optimal. (Redis CoW by forking the process is much
> more performant ...)


## Data Structures

Redi/S is using just regular Swift datastructures
(and is therefore also a test of the scalability of those).

Most importantly this currently uses Array's for lists! 🤦‍♀️
Means:
RPUSH is reasonably fast, but occasionally requires a realloc/copy.
LPUSH is very slow.

Plan: To make LPUSH faster we could use the NIO.CircularBuffer.
[If we get some more methods](https://github.com/apple/swift-nio/issues/279)
on it.

The real fix is to use proper lists etc.
But if we approach this, we also need to reconsider CoW.


## Concurrency

How many eventloop threads are the sweet spot?

- Is it 1, avoiding all synchronization overhead?
- Is it `System.coreCount`, putting all CPUs to work?
- Is it `System.coreCount / 2`, excluding hyper-threads?

We benchmarked the server on 
a 13" MBP - 2 Cores, 4 hyperthreads,
and on
a MacPro 2013 - 4 Cores, 8 hyperthreads.

Surprisingly *2* seems to be the sweet spot.
Not quite sure yet why.
Is that when the worker thread is saturated? It doesn't seems so.

Running the MT-aware version on a single eventloop thread halves the 
performance.

Notably running a SingleThread optimized version still reached ~75% of the
dual thread variant (but at a lower CPU load).


## Tested Optimizations

Trying to improve performance, we've tested a few setups we thought might
do the trick.

### Command Name as Data

This version uses a Swift `String` to represent command names.
That appears to be wasteful (because a Swift string is an expensive Unicode
String),
but actually seems to have no measurable performance impact.

We tested a branch in which the command-name is wrapped in a plain `Data`
and used that as a key.

Potential follow up:
Command lookup seems to play no significant role,
but one thing we might try is to wrap the ByteBuffer in a small struct
w/ an efficient and targetted, case-insensitive hash.

### Avoid NIO Pipeline for non-BB

The "idea" in NIO is that you form a pipeline of handlers.
At the base of that pipeline is the socket, which pushes and receives
`ByteBuffer`s from that pipeline.
The handlers can then perform a set of transformations.
And one thing they can do, is parse the `ByteBuffer`s into higher level 
objects.

This is what we did originally (0.5.0) release:

```
Socket 
  =(BB)=>
    NIORedis.RESPChannelHandler 
      =(RESPValue)=>
        RedisServer.RedisCommandHandler
      <=(RESPValue)
    NIORedis.RESPChannelHandler 
  <=(BB)=
Socket
```

When values travel the NIO pipeline, they are boxed in `NIOAny` objects.
Crazy enough just this boxing has a very high overhead for non-ByteBuffer
objects, i.e. putting `RESPValue`s in and out of `NIOAny` while passing
them from the parser to the command handler, takes about *9%* of the runtime
(at least in a sample below ...).

To workaround that, `RedisCommandHandler` is now a *subclass*
of `RESPChannelHandler`.
This way we never wrap non-ByteBuffer objects in `NIOAny` and the pipeline
looks like this:
Socket 
  =(BB)=>
    RedisServer.RedisCommandHandler : NIORedis.RESPChannelHandler 
  <=(BB)=
Socket
```

We do not have a completely idle system for more exact performance testing,
but this seems to lead to a 3-10% speedup (measurements vary quite a bit).


### Worker Sync Variants

#### GCD DispatchQueue for synchronization

Originally the project used a `DispatchQueue` to synchronize access to the
in-memory databases.

The overhead of this is pretty high, so we switched to a RWLock for a ~10% speedup.
But you don't lock a NIO thread you say?!
Well, this is all very fast in-memory database access which in *this specific case*
is actually faster than the capturing a dispatch block and submitting that to a queue
(which also involves a lock ...)

#### NIO.EventLoop instead of GCD

We wondered whether a `NIO.EventLoop` might be faster then a `DispatchQueue`
as the single threaded synchronization point for the worker thread
(`loop.execute` replacing `queue.async`).

There is no measurable difference. GCD is a tinsy bit faster.

#### Single Threaded

Also tested a version with no threading at all (Node.js/Noze.io style).
That is, not just lowering the thread-count to 1, but taking out all `.async`
and `.execute` calls.

This is surprisingly fast, the synchronization overhead of `EventLoop.execute`
and `DispatchQueue.async` is very high.

Running a single-thread optimized version still reached ~75% of the
dual thread variant (but at a lower CPU load).

Follow up:
If we would take out CoW data structures, which wouldn't be necessary anymore
in the single-threaded setup, it sounds quite likely that this might go faster
than the threaded variant.


## Instruments

I've been running Instruments on Redi/S. With SwiftNIO 1.3.1.
Below annotated callstacks.

Notes:
- just `NIOAny` boxing (passing RESPValues in the NIO pipeline) has an overhead 
  of *9%*!
  - this probably implies that just directly embedding NIORedis into
    RedisServer would lead to that speedup.
- from `flush` to `Posix.write` takes NIO another 10%

### Single Threaded

This is the single threaded version, to remove synchronization overhead
from the picture.

```
redis-benchmark -p 1337 -t get -n 1000000 -q
```

- Selector.whenReady: 98.4%
    - KQueue.kevent 2.1%
    - handleEvent 95.4%
        - readFromSocket 89.8%
            - Posix.read 8.7%
            - RedisChannel.read() 77.2%
                - decodedValue(_:in:) 71.2%
                    - 1.3% alloc/dealloc
                    - decodedValue(:in:) 68.8%
                        - wrapInbountOut: 1.8%
                        - RedisCommandHandler: 66.2% (parsing ~11%)
                            - unwrapInboundIn: 1.7%
                            - parseCommandCall: 4.7%
                                - Dealloc 1.3%
                                - stringValue 1.3% (getString)
                                - Uppercased 0.7%
                            - callCommand: 55.3%
                                - Alloc/dealloc 2%
                                - withKeyValue 51.6%
                                    - release_Dealloc - 1.6%
                                    - Data init, still using alloc! 0.2%
                                    - Commands.GET 48.4%
                                        - ctx.write(46.8%)
                                            - writeAndFlush 45%
                                                - RedisChannelHandler.write 8%
                                                    - Specialised RedisChannelHandler.write 6.7%
                                                        - unwrapOutboundIn 2.6%
                                                        - wrapOutboundOut 0.6%
                                                        - ctx.write 2.8%
                                                            - Unwrap 2.5%
                                                - Flush 36.2%
                                                    - pendingWritesManager 32.7%
                                                        - Posix.write 26.3%
                                            - NIOAny 1.2%
                                                - Allocated-boxed-opaque-existential

### Multi Threaded w/ GCD Worker Thread

- Instruments crashed once, so numbers are not 100% exact, but very close

```
redis-benchmark -p 1337 -t set -n something -q
```

- GCD: worker queue 17.3%
    - GCD overhead till callout: 3%
    - worker closure: 14.3%
    - SET: 13.8%, 12.8% in closure
        - ~2% own code
        - 11% in:
            - 5% nativeUpdateValue(_:forKey:)
            - 1.3% nativeRemoveObject(forKey:)
            - 4.7% SelectableEventLoop.execute (malloc + locks!)
    - Summary: raw database ops: 5.3%, write-sync 4.7%, GCD sync 3%+, own ~2%
- EventLoops: 82.3%, .run 81.4%
    - PriorityQueue:4.8%
    - alloc/free 2.1%
    - invoke
        - READ PATH - 37.9%
            - selector.whenReady 36.1%
                - KQueue.kevent(6.9%)
                - handleEvent (28.7%)
                    - readComplete 2.1%
                        - flush 1.4%              **** removed flush in cmdhandler
                    - readFromSocket(25%)
                        - socket.read 5.3%
                            - Posix.read 4.9%
                        - alloc 0.7%
                        - invokeChannelRead 18.2%
                            - RedisChannel.read 17.6% (Overhead: Parser=>Cmd: 5.2%) **
                                - 0.4% alloc, 0.3% unwrap
                                - BB.withUnsafeRB 16.6% (Parser)
                                    - decoded(value:in) 14.9%
                                        - dealloc 0.5%, ContArray.reserveCap 0.2%
                                        - decoded(value:in:) 13.5% (recursive top-level array!)
                                            - wrapInboundOut 0.7%
                                            - fireChannelRead 12.6%
                                                - RedisCmdHandler 12.4% **
                                                    - unwrapInboundIn 1.1%
                                                    - parseCmdCall 2.1%
                                                        - RESPValue.stringValue 0.6%
                                                        - dealloc 0.6%
                                                        - upper 0.4%
                                                        - hash 0.1%
                                                    - callCommand 6.7%
                                                        - RESPValue.keyValue 1.4%
                                                            - BB.readData(length:) DOES AN alloc?
                                                                - the release closure!
                                                        - Commands.SET 4.8%
                                                            - ContArray.init 0.2%
                                                            - runInDB 3.3% (pure sync overhead)
        - WRITE PATH - 31.1% (dispatch back from DB thread)
            - Commands.set 30.4%
                - cmdctx.write 30% (29.6% specialized)  - 1.2% own rendering overhead
                    - writeAndFlush 28.5%
                        - flush 18.7%
                            - socket flush 17.9%
                                - Posix.write 14%
                        - write 9.6%
                            - RedisChannelHandler.write 9.6%
                                - specialised 8.7% ???
                                - ByteBuffer.write - 3%
                                - unwrapOutboundIn - 1.4%
                                - ctx.write 1.2% (bubble up)
                                - integer write 1% (buffer.write(integer:endianess:as:) ****
                    - NIOAny 0.8%
        - 1.5% dealloc
