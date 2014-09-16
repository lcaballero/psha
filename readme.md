# Introduction [![Build Status](https://travis-ci.org/lcaballero/psha.svg?branch=master)](https://travis-ci.org/)

Psha is an in memory cache for JavaScript (well Node.js in particular).  Pronounced, as if by a kung-fu panda,
"PpppssshhAaaaa-Aaa". Simplified for use in a require() call to just: `Psha` (no guessing as to number for each
of the letters).

Psha is smart about how it issues update() calls.  For instance, if a client were to issue requests for items
that had int IDs in this order `[1,2,3]` then `[4,5,6]`, followed by `[3,4]` it would only issue update
calls to fill the first two requests and then use the results to fill the third since `[3,4]` is a subset of
both the first and second update calls.


## Installation

```
%> npm install psha --save
```


## Configuration

Each Psha instance can be configured with a number of options.  These options are also defaulted
where reasonable.  The only required option is the update(key,cb) function which populates the
cache on cache misses.

```coffeescript
options = {
    update: (keys, cb) ->
    ttl: 20*1000
    timeout: 30*1000
    clear: (key, value, age) ->
    logger:
        log: (args...) ->
        debug: (args...) ->
        error: (args...) ->
        warning: (args...) ->
}
cache = new Psha(options)
cache.get([id1, id2, id3, ... , id4], (err, res) ->)
```

## Usage

```coffeescript
options = {
    update: (keys, cb) -> Database.runProc(keys, cb)
}
cache = new Psha(options)
cache.get([id1, id2], (err, res) ->
    # Will respond with items from the cache if id1 and id2 are both in the cache.
    # For a cache miss the update function will be ran.

    ... do something with result ...
)
```

## License

See license file.

The use and distribution terms for this software are covered by the
[Eclipse Public License 1.0][EPL-1], which can be found in the file 'license' at the
root of this distribution. By using this software in any fashion, you are
agreeing to be bound by the terms of this license. You must not remove this
notice, or any other, from this software.


[EPL-1]: http://opensource.org/licenses/eclipse-1.0.txt
[checkArgs]: http://docs.guava-libraries.googlecode.com/git/javadoc/com/google/common/base/Preconditions.html
