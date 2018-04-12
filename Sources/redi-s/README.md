<h2>Redi/S - Server Executable
  <img src="http://zeezide.com/img/redi-s-logo-286x100.png"
       align="right" width="286" height="100" />
</h2>

`redi-s` is a very small executable based on the 
[RedisServer](../RedisServer/)
module.
The actual functionality is contained in the module,
the tool just parses command line options and starts the server.

## How to build

If you care about performance, do a `release` build:

```shell
$ swift build -c release
```

## How to run

```
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

Options:

- `-h` / `--help`, print help
- `-p` / `--port`, select a port, e.g. `-p 8888`

## TODO

- [ ] load configuration file

### Who

Brought to you by
[ZeeZide](http://zeezide.de).
We like
[feedback](https://twitter.com/ar_institute),
GitHub stars,
cool [contract work](http://zeezide.com/en/services/services.html),
presumably any form of praise you can think of.
