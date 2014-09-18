_      = require 'lodash'
moment = require 'moment'

_30sec = 30*1000
_20sec = 20*1000
_1sec  = 1000


class Psha
  ###
    @opts {object} A configuration object that can include the following
      properties: update, clear, and ttl.

    @opts.update {function} With the signature: (keys, cb) ->
      Where cb is a function (err, pairs) -> recieving an object mapping keys
      to objects to be added to the internal cache of this instance.

    @opts.clear  {function} A callback (keys) -> that will be invoked with the keys that
      will be removed from the internal cache.
  ###
  constructor: (opts, defaults) ->
    { ttl, update, clear, timeout, logger, timeoutInterval } = opts

    # Used to mimick a seperate set of default for testing.  For instance, setting
    # the default minimim timeout to something more reasonable for testing.
    defaults = _.defaults({}, defaults or {}, Psha.defaults)

    Psha.runningCaches.push(this)

    if !update?
      throw new Error('An update() method is required.')

    # TODO: change these to defineProperty calls so that they can
    # TODO: be read-only, and exposed via normal property access
    # TODO: and getTtl() can go away
    @_ttl     = ttl or defaults.ttl
    @_timeout = Number(timeout or defaults.timeout)

    if !@_timeout or !@_timeout? or @_timeout < defaults.minTimeout
      throw new Error('Timeout must be greater than or equal to 1 second.')

    @_update        = update
    @_clear         = clear or defaults.clear
    @_cache         = {}
    @_pending       = {}
    @_defaults      = defaults
    @log            = logger or defaults.logger
    @_ttlTimer      = setInterval((=> @_clearExpiredEntries()), @_ttl / 2)

    # Request timeouts are checked every second, but the duration before a timeout
    # is fired is controlled by the timeout provided in the options and defaults.
    @_timeoutInterval = timeoutInterval or defaults.timeoutInterval
    @_timeoutTimer    = setInterval((=> @_clearOverdueRequests()), @_timeoutInterval)

  getTimeout: -> @_timeout
  getTtl: -> @_ttl
  isEmpty: -> _.keys(@_cache)?.length is 0
  hasLogger: -> @log?
  getLogger: -> @log
  hasPendingRequests: -> _.keys(@_pending)?.length > 0
  getPendingKeys: -> _.keys(@_pending)
  clearTimers: ->
    clearInterval(@_ttlTimer)
    clearInterval(@_timeoutTimer)

  _findOverdueRequests:  (pending, timeout, now) ->
    pending ?= @_pending
    timeout ?= @_timeout
    now      = moment().valueOf()
    overdue  = {}

    for k,reqs of pending
      aged  = _.filter(reqs, (req) -> (now - req.timestamp) > timeout)
      if aged.length > 0
        for old in aged
          if overdue[old.id]? then continue
          overdue[old.id] = old

    overdue

  ###
    Produces a new pending map where the keys are those keys where an update
    was made and the values are a list of requests the request that should
    produce the given key.

    { 'key-requested-1' : [ req-1-needing-key-1, req-2-needing-key-1 ] }
  ###
  _reviseOverdueRequests: (pending, timeout, now) ->
    pending   ?= @_pending
    timeout   ?= @_timeout
    now       ?= moment().valueOf()
    awaiting   = {}

    for k,reqs of pending
      young = _.filter(reqs, (req) -> (now - req.timestamp) <= timeout)
      if young.length > 0
        awaiting[k] = young

    awaiting

  _clearOverdueRequests: (pending, timeout, now) ->
    now     ?= moment().valueOf()
    overdue  = @_findOverdueRequests(pending, timeout, now)
    awaiting = @_reviseOverdueRequests(pending, timeout, now)

    @_pending = awaiting

    for k,old of overdue
      old.callback(new Error("Request has timed out for keys: " + JSON.stringify(old.misses)))

  ###
    Adds cache entries using the key/value pairs provided; and, if a timestamp @now
    is provided it will be used for the timestamp for all of the entries.  @now is
    intended to be used for testing, but it can also be used to reduce the ttl of
    entries added using this method.

    @pairs {object} A list of key/value pairs to add to the cache.
    @now {utc-timestamp} Optional, and if provided will be the timestamp used for
        each of the values add to the cache.
  ###
  fillCache: (pairs, now) ->
    if !_.isPlainObject(pairs)
      throw new Error('Cache data is expected to be an object of key,value pairs.')

    now ?= moment().valueOf()

    for k,v of pairs
      @_cache[k] =
        value: v
        timestamp: now
    @

  ###
    An item is considered in the cache if 1) the key is in the lookup map, 2) the value is
    not null or undefined, and 3) if the timestamp of the entry is less than the ttl.

    @key {string} A key to use to look up a value in the cache.
    @now {utc-long} A timestamp to use for comparison with the timestamp of the found cache
        entry.  If a timestamp is not provided 'now' is used.  If 'now' minus the timestamp of the
        entry is greater than the ttl this method returns false.
  ###
  hasItem: (key, now) ->
    now  ?= moment().valueOf()
    item  = @_cache[key]
    age   = if item? then now - item.timestamp else @_ttl
    item? and age < @_ttl

  ###
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

    Signature: get([name], keys, cb)

    @params name {string} A name to
  ###
  get: ->
    if arguments.length > 2
      [ name, keys, cb ] = arguments
    else
      [ keys, cb ] = arguments
      name = 'un-named'

    now     = moment().valueOf()
    keys    = [].concat(keys)

    # TODO: instead, just loop and gather an object with {misses, hits}
    misses  = _.filter(keys, (id) => !@hasItem(id, now))
    hits    = _.filter(keys, (id) => @hasItem(id, now))

    if misses.length is 0
      res = _.map(hits, (f) => @_cache[f].value)
      cb(null, res)
    else
      values = _.map(hits, (f) => @_cache[f].value)

      @_addPending(
        cb: cb, name: name, ts: now, req: keys,
        hits: hits, misses: misses, values: values)

      removePending = (err, pairs) =>
        if err?
          @log.error(err)
          cb(err, null)
        else
          @_clearPending(pairs)

      @_update(misses, removePending)

    @

  _reviseCacheEntries: (cache, ttl, clear) ->
    now = moment().valueOf()

    revised = {}
    for key,entry of cache
      { timestamp } = entry
      if now - timestamp <= ttl
        revised[key] = entry
      else
        clear(key, entry.value, now - entry.timestamp)

    revised

  _clearExpiredEntries: (cache, ttl) ->
    cache ?= @_cache
    ttl   ?= @_ttl
    clear = (key, value, age) => @_clear(key, value, age)

    @_cache = @_reviseCacheEntries(cache, ttl, clear)

  _revisePending: (pending, hasItem) ->
    pending ?= @_pending
    hasItem ?= (id, ts) => @hasItem(id, ts - 1)

    now = moment().valueOf()

    revised = {}
    realized = {}

    for k,reqs of pending
      for req in reqs
        haveAll = _.all(req.misses, (miss) -> hasItem(miss, now - 1))
        if haveAll then realized[req.id] = req

    for k,reqs of pending
      unfilled = _.filter(reqs, (req) -> !realized[req.id]?)
      if unfilled?.length > 0
        revised[k] = unfilled

    { revised: revised, realized: realized }

  ###
    Once a request is filled we can traverse the pending sets and see if
    any of the pending sets are fully realized, and then fire their callback.

    Over time the timeout mechanism will fire and determine that the request
    hasn't been fullfilled and clear the request from the pending map.
  ###
  _clearPending: (pairs) ->

    @fillCache(pairs) # Add result to current cache

    { realized, revised } = @_revisePending(@_pending, (key, now) => @hasItem(key, now))
    @_pending = revised

    for k,v of realized
      if v.callback?
        all     = [ v.values, _.map(v.misses, (key) => @_cache[key].value) ]
        values  = _.flatten( all )

        # Check if the callback will take 3 parameters the first of which
        # is considered a logical 'name' provided with the get() call.
        if v.callback.length is 3
          v.callback(v.name, null, values)
        else
          v.callback(null, values)
      else
        @log.error("Pending request didn't have a callback???")


  ###
    The pending map is a structure where the keys are those that have been
    requested via the provided update() method.  Each key maps to a request
    which has the following keys:

      {
        timstamp: utc stamp when the get() request was made
        request: [ list-of-keys-of-initial-request ]
        hits:  [ keys that were in the cache when get() request was made ]
        misses: [ pending list of keys ]
        values: [ values for the hits ]
      }

    The union of hits and misses should equal the request list.  In other words:
    hits are those which the cache had, and misses are those the cache didn't have
    at the moment when the get() request was made.

    During each 'timeout' cycle the pending list is checked.  Any request for
    which the timeout is reached an error is fired with a timeout message.  If
    a request has been timed out then all other requests which share the same
    keys are also timed out.
  ###
  _addPending: ({cb, name, ts, req, hits, misses, values}) ->

    if !cb?
      throw new Error("A callback is required to create a pending result.")

    pending =
      id        : JSON.stringify(misses)
      name      : name
      callback  : cb
      timestamp : ts
      request   : req
      hits      : hits
      misses    : misses
      values    : values

    for key in misses
      if !@_pending[key]? then @_pending[key] = []
      @_pending[key].push(pending)


Psha.runningCaches = []
Psha.defaults = {
  ttl             : _30sec
  timeout         : _20sec
  timeoutInterval : _1sec
  minTimeout      : _1sec
  clear         : (key, value, age) ->
  logger : (->
    log = console.log
    info  : (args...) ->
      log(args...)
    debug : (args...) ->
      log(args...)
    warn  : (args...) ->
      log(args...)
    error : (args...) ->
      log(args...))()
}

module.exports =  Psha