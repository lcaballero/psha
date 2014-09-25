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
  update: (keys, cb) -> Database.runProc(keys, (err, res) ->
    if err?
      cb(err, null)
    else
      pairs = {}
      for r in res
        pairs[r.id] = r
      pairs
  )
}
cache = new Psha(options)
cache.get([id1, id2], (err, res) ->
  # Will respond with items from the cache if id1 and id2 are both in the cache.
  # For a cache miss the update function will be ran.

  ... do something with result ...
)
```

## API

### getTimeout: ->
Accessor to get the currently set amount of timeout.

### getTtl: ->
Access to get the time to live (ttl) for applied to all entries.

### isEmpty: ->
Determines if the current cache is entry.

### hasLogger: ->
Reports true if the current cache was provided a logger.

### getLogger: ->
Gets the logger provided during setup.

### hasPendingRequests: ->
Returns true if the cache is currently awaiting request for key/value pairs.

### getPendingKeys: ->
Provides the list of keys that the cache is awaiting an update for.

### clearTimers: ->
Clears any timers set in the cache.  This is mostly surfaced for clean up during
testing where each time should be cleared during an `afterEach`.

### fillCache: (pairs, now) ->
Adds cache entries using the key/value pairs provided; and, if a timestamp @now
is provided it will be used as the timestamp for all of the entries.  @now is
intended to be used for testing, but it can also be used to reduce the ttl of
entries added using this method.

@pairs {object} A list of key/value pairs to add to the cache.
@now {utc-timestamp} Optional, and if provided will be the timestamp used for
    each of the values add to the cache.

###  hasItem: (key, now) ->
An item is considered in the cache if 1) the key is in the lookup map, 2) the value is
not null or undefined, and 3) if the timestamp of the entry is less than the ttl.

@key {string} A key to use to look up a value in the cache.
@now {utc-long} A timestamp to use for comparison with the timestamp of the found cache
    entry.  If a timestamp is not provided 'now' is used.  If 'now' minus the timestamp of the
    entry is greater than the ttl this method returns false.

### get([name], keys, cb): ->

This method determines the keys that the cache doesn't already posses and then
makes an update to request the cache misses, while additionally saving
the cache hits that were available when this call was invoked, because
between the time the update call was made and the the result is returned
the cache items might be cleared based on the ttl for those items.

This method also needs to track the keys that were requested and not
request them multiple times when several calls to get() are made with the same
requested keys.

This function will track a set of keys and invoke the cb once the entire set
of keys is found.

## Defaults API
These values are used to reasonably default values for the cache that were omitted
during construction.

- Psha.defaults.ttl
- Psha.defaults.timeout
- Psha.defaults.timeoutInterval
- Psha.defaults.minTimeout
- Psha.defaults.clear
- Psha.defaults.logger

## License

See license file.

The use and distribution terms for this software are covered by the
[Eclipse Public License 1.0][EPL-1], which can be found in the file 'license' at the
root of this distribution. By using this software in any fashion, you are
agreeing to be bound by the terms of this license. You must not remove this
notice, or any other, from this software.


[EPL-1]: http://opensource.org/licenses/eclipse-1.0.txt
[checkArgs]: http://docs.guava-libraries.googlecode.com/git/javadoc/com/google/common/base/Preconditions.html
