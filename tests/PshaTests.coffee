moment        = require('moment')
_             = require 'lodash'
chai          = require('chai')
expect        = chai.expect
sinonChai     = require 'sinon-chai'
chai.use(sinonChai)
sinon         = require 'sinon'
Psha          = require '../src/Psha'


console.json = ((replacer, space) -> (args...) ->
  console.log.apply(console, _.map(args, (a) -> JSON.stringify(a, replacer, space))))(null, '  ')


describe 'PshaTest =>', ->

  makeIdCache = (keys) ->
    acc = {}
    for id in keys
      acc['key-' + id] = 'value-' + id
    acc

  keysToPairs = (keys) ->
    acc = {}
    for k in keys
      acc[k] = ("" + k).replace(/key-/, 'value-')
    acc

  toKeyIds = (n) ->
    _.keys(makeIdCache(n))

  update = (n) -> (keys, cb) ->
    expect(keys).to.have.length(n)
    cb(null, keysToPairs(keys))

  afterEach ->
    for r in Psha.runningCaches
      r.clearTimers()


  describe 'caching array results =>', ->

    it 'should lodash examples', ->
      console.log('lodash map', _.map([], (f) -> 1))

    it 'should cache array results', (done) ->
      opts = update : (keys, cb) ->
        lookup = {}
        for a in keys
          lookup[a] = [a]
        cb(null, lookup)

      cache = new Psha(opts)

      cache.get([1], (e1, r1) ->
        cache.get([1], (e2, r2) ->
          expect(e2).to.not.exist

          expect(r1).to.have.length(r2.length)
          expect(_.isArray(r2[0]))
          expect(_.isArray(r1[0])).to.be.true
          expect(_.isArray(r2[0])).to.be.true
          done()
        )
      )

    it 'should produce single array', (done) ->
      opts = update : (keys, cb) ->
        lookup = {}
        for a in keys
          lookup[a] = [a]
        cb(null, lookup)

      cache = new Psha(opts)

      cache.get([1], (err, res) ->
        expect(err).to.not.exist
        expect(_.isArray(res)).to.be.true
        expect(res[0][0]).to.equal(1)
        done()
      )

  describe 'ttl =>', ->

    it 'should produce values that would have otherwise have been removed between ttl and recieving result', (done) ->
      ttl   = 300
      delta   = 50

      opts  = ttl: ttl, update: (keys, cb) ->
        setTimeout(->
          cb(null, keysToPairs(keys))
        , ttl)

      now     = moment().valueOf()
      cache   = new Psha(opts)
      expire  = now - cache.getTtl() + delta

      cache.fillCache(makeIdCache([1..10]), expire)

      cache.get(toKeyIds([7..14]), (err, res) ->
        expect(res).to.have.length([7..14].length)
        expect(cache.isEmpty()).to.be.false

        for id in toKeyIds([7..10])
          expect(cache.hasItem(id), "shouldn't have id: " + id).to.be.false

        for id in toKeyIds([11..14])
          expect(cache.hasItem(id), "should have id: " + id).to.be.true

        done()
      )

    it 'should fire the clear callback when items are removed from the cache via ttl', (done) ->
      ttl     = 300
      delta   = 100
      cleared = {}

      opts  =
        ttl: ttl,
        clear: (key, value, timestamp) ->
          cleared[key] = value
        update: (keys, cb) ->
          setTimeout(->
            cb(null, keysToPairs(keys))
          , ttl)

      now     = moment().valueOf()
      cache   = new Psha(opts)
      older   = now - cache.getTtl() - delta
      newer   = now - cache.getTtl() + delta + delta

      cache.fillCache(makeIdCache([1..7]), older)
      cache.fillCache(makeIdCache([11..20]), newer)

      cache.get(toKeyIds([11]), (err, res) -> )

      setTimeout(->
        expect(_.keys(cleared), "should have cleared a number of keys: " + JSON.stringify(_.keys(cleared)))
          .to.have.length([1..7].length)
        expect(_.keys(cache._cache), "should have reduced cache keys: " + JSON.stringify(_.keys(cache._cache)))
          .to.have.length([11..20].length)
        done()
      , ttl)

  describe '_reviseCacheEntries =>', ->

    it 'should clear old entries', (done) ->
      now     = moment().valueOf()
      opts    = update: ->
      cache   = new Psha(opts, ttl: 300)


      expired = now - cache.getTtl() - 50

      # fills cache with items that are nearly expired
      cache.fillCache(makeIdCache([1..10]), expired)
      checkDelay = cache.getTtl() + 50

      setTimeout(->
        ts = moment().valueOf()
        expect(cache.isEmpty(), 'cache should be empty').to.be.true
        done()
      , checkDelay)

    it "should leave newer entries", (done) ->
      opts    = update: ->
      cache   = new Psha(opts, ttl: 600)

      now     = moment().valueOf()
      delta   = 100
      expire  = cache.getTtl() - delta

      # fills cache with items that are nearly expired
      cache.fillCache(makeIdCache([1..10]), now - expire)
      checkDelay = delta

      setTimeout(->
        expect(cache.isEmpty(), 'cache should be empty').to.be.false
        done()
      , checkDelay)

    it "should leave newer entries and clear out expired (at the same time)", (done) ->
      opts    = update: ->
      cache   = new Psha(opts, ttl: 600)

      now     = moment().valueOf()
      delta   = 100
      newer   = now - cache.getTtl() + delta
      expried = now - cache.getTtl() - delta

      # fills cache with items that are nearly expired
      cache.fillCache(makeIdCache([1..10]), newer)
      cache.fillCache(makeIdCache([11..20]), expried)

      setTimeout(->
        expect(cache.isEmpty(), 'cache should be empty').to.be.false

        ts = moment().valueOf()

        for id in toKeyIds([11..20])
          expect(cache.hasItem(id, ts), "shouldn't have id: " + id).to.be.false

        for id in toKeyIds([1..10])
          expect(cache.hasItem(id, ts), "should have id: " + id).to.be.true

        done()
      , delta / 2)


  describe 'pending =>', ->

    it 'should have pending requests for cache misses', (done) ->
      fill  = _.keys(makeIdCache([1..10]))
      opts  = update: (keys, cb) ->
        setTimeout(->
          cb(null, keysToPairs(keys))
        , 100)

      pending = new Psha(opts).get(fill, (err, res) -> done()).getPendingKeys()

      expect(pending).to.have.length(fill.length)

      for key in pending
        expect(key in pending).to.be.true

    it 'should no longer have pending requests after receiving results for cache misses', (done) ->
      fill  = _.keys(makeIdCache([1..10]))
      opts  = update: (keys, cb) ->
        setTimeout(->
          cb(null, keysToPairs(keys))
        , 100)

      cache = new Psha(opts)
      cache.get(fill, (err, res) ->
        expect(cache.hasPendingRequests(), "shouldn't have pending keys").to.be.false
        done())


  describe 'multiple get() calls =>', ->

    it 'should initially call update() with cache misses', (done) ->
      # Sets are unequal so that the total is never an over count of one of the sets.
      f1    = _.keys(makeIdCache([1..3]))
      f2    = _.keys(makeIdCache([4..9]))
      f3    = _.keys(makeIdCache([3,4]))

      delay = 100

      opts  = update: (keys, cb) ->
        setTimeout(->
          cb(null, keysToPairs(keys))
        , delay += delay)

      cache = new Psha(opts)

      vals  = []
      names = ['f1', 'f2', 'f3']
      total = (f1.length + f2.length + f3.length)

      ###
        Asserts: done() is only called if we recieve enough values to fill all requests
        and that we actually are provided with results that are associated with requests
        we made and not duplicates.
      ###
      req = (name, err, res) ->
        vals  = vals.concat(res)
        names = _.filter(names, (n) -> name.substring(0, n.length) isnt n)
        info  = "Name: '#{name}', vals: #{JSON.stringify(vals)}, and names: #{JSON.stringify(names)}"

        if vals.length is total and names.length is 0
          done()
        else
          expect(vals.length is total and names.length > 0,
            "Can't have received all values but not gotten all requests." + info).to.be.false
          expect(names.length is 0 and vals.length isnt total,
            "Can't have gotten all requests but not all values." + info).to.be.false

      cache.get("f1 #{JSON.stringify(f1)}", f1, req)
      cache.get("f2 #{JSON.stringify(f2)}", f2, req)
      cache.get("f3 #{JSON.stringify(f3)}", f3, req)

    it "should make call only misses that haven't already been requested", ->
      keys = []
      opts = update: (ids, cb) ->
        keys = keys.concat(ids)
        cb(null, keysToPairs(ids))

      cache = new Psha(opts)
      cache.get(toKeyIds([1..4]), (err, res) -> )
      cache.get(toKeyIds([3..8]), (err, res) -> )
      cache.get(toKeyIds([7..10]), (err, res) -> )

      # Shouldn't have over lap with 3, 4, 7, and 8.  If we have overlap, we'll
      # have a count that exceeds a 1:1 mapping of ids to update calls
      expect(keys).to.have.length([1..10].length)

      hasRequestedAll = _.all(toKeyIds([1..10]), (id) -> id in keys)
      expect(hasRequestedAll).to.be.true

    describe 'clearPending =>', ->

      c1 = null
      c2 = null
      c3 = null
      c4 = null

      addPending = (cache, name, ids, ts) ->
        cache._addPending({
          cb      : ->
          name    : name
          ts      : ts
          req     : _.keys(makeIdCache(ids))
          hits    : []
          misses  : _.keys(makeIdCache(ids))
          values  : []
        })

      checkFill = (revised, realized, cache, filledIds, pendingIds) ->
        expect(revised, 'has revised').to.be.ok
        expect(realized, 'has realized').to.be.ok

        expect(_.keys(revised), 'should have 1..4 pending').to.have.length(pendingIds.length)
        expect(_.values(realized)).to.have.length(1)
        expect(_.values(realized)[0].misses).to.include.members(_.keys(makeIdCache(filledIds)))

        cache._pending = revised
        pending = _.keys(makeIdCache(pendingIds))
        expect(cache.getPendingKeys()).to.have.length(pending.length)
        expect(cache.getPendingKeys()).to.include.members(pending)

      before ->
        c1 = new Psha(update:->)
        now = moment().valueOf()

        addPending(c1, '[1..3]', [1..3], now)

        c2 = new Psha(update:->)
        addPending(c2, '[1..3]', [1..3], now)
        addPending(c2, '[4..9]', [4..9], now)

        c3 = new Psha(update:->)
        addPending(c3, '[1..3]', [1..3], now)
        addPending(c3, '[4..9]', [4..9], now)
        addPending(c3, '[3,4]' , [3,4], now)

        c4 = new Psha(update:->)
        addPending(c4, '[1..3]', [1..3], now)
        addPending(c4, '[4..9]', [4..9], now)
        addPending(c4, '[3,4]' , [3,4], now)

      it 'check setup', ->
        caches = [
          {cache:c1, ids:[1..3]}
          {cache:c2, ids:[1..9]}
          {cache:c3, ids:[1..9]}
        ]
        for c in caches
          { cache, ids } = c
          expect(cache.isEmpty()).to.be.true
          expect(cache.hasPendingRequests()).to.be.true
          expect(cache.getPendingKeys()).to.include.members(_.keys(makeIdCache(ids)))

      it 'empty cache with pending first request should clear entire pending list', ->
        filledIds = [1..3]; pendingIds = []

        c1.fillCache(makeIdCache(filledIds))

        { revised, realized } = c1._revisePending()

        checkFill(revised, realized, c1, filledIds, pendingIds)

      it 'should clear pending in a 2 request scenario with no overlapping keys', ->
        filledIds   = [1..3]
        pendingIds  = [4..9]

        c2.fillCache(makeIdCache(filledIds))

        { revised, realized } = c2._revisePending()

        checkFill(revised, realized, c2, filledIds, pendingIds)

      it "with overlapping keys should clear keys which don't have pending request keys", ->
        filledIds = [1..3]; pendingIds = [3..9]

        c3.fillCache(makeIdCache(filledIds))

        { revised, realized } = c3._revisePending()

        checkFill(revised, realized, c3, filledIds, pendingIds)

      it "reqs 1,2,3 recieved 2 should leave reqs 1,3", ->
        ### Has 3 reqs, and recieves #2. ###
        filledIds = [4..9]; pendingIds = [1..4]

        expect(c4.getPendingKeys()).to.include.members(_.keys(makeIdCache(filledIds)))

        c4.fillCache(makeIdCache(filledIds))

        { revised, realized } = c4._revisePending()

        checkFill(revised, realized, c4, filledIds, pendingIds)

        ### Has 3 reqs, and recieves #3. ###
        filledIds = [3,4]; pendingIds = [1..3]

        expect(c4.getPendingKeys()).to.include.members(_.keys(makeIdCache(filledIds)))

        c4.fillCache(makeIdCache([3,4]))

        { revised, realized } = c4._revisePending()

        checkFill(revised, realized, c4, filledIds, pendingIds)


  describe "timeout =>", ->

    describe '_findOverdueRequests =>', ->

      createPending = (misses, ts, cb) ->
        cb ?= (->)
        ({
          id        : JSON.stringify(_.map(misses, (id) -> 'key-' + id))
          misses    : _.map(misses, (id) -> 'key-' + id)
          timestamp : ts
          callback  : cb
        } for id in misses)

      createPendingLookup = (reqs) ->
        rv = {}
        for req in reqs
          for id in req.misses
            if !rv[id]? then rv[id] = []
            rv[id].push(req)
        rv

      _300ms = 300
      _250ms = 250
      _200ms = 200
      _100ms = 100

      it "should determine that some pending requests have timed out", ->
        opts    = update : (->)
        now     = moment().valueOf()
        cache   = new Psha(opts)

        p1      = createPending(  [1..5], now - _300ms) # +5
        p2      = createPending([11..20], now - _250ms) # +10
        p3      = createPending([31..60], now - _100ms) # +0
        p4      = createPending([11..15], now - _100ms) # +0

        pending = createPendingLookup(_.flatten([p1, p2, p3, p4]))

        # Should consider everything with age > 200ms as timedout
        overdue = cache._findOverdueRequests(pending, _200ms)

        expect(_.keys(overdue)).to.have.length([p1, p2].length)

      it "should fire callback with timeout error for those overdue", (done) ->
        errs    = []
        opts    = update : (->)
        cb      = (err) ->
          errs.push(err)
          if errs.length is [p1,p2].length then done()

        now     = moment().valueOf()
        cache   = new Psha(opts)

        p1      = createPending(  [1..5], now - _300ms, cb) # +5
        p2      = createPending([11..20], now - _250ms, cb) # +10
        p3      = createPending([31..60], now - _100ms, cb) # +0
        p4      = createPending([11..15], now - _100ms, cb) # +0

        pending = createPendingLookup(_.flatten([p1, p2, p3, p4]))

        # Should consider everything with age > 200ms as timedout
        cache._clearOverdueRequests(pending, _200ms)

      it "pending request should reflect less those that are overdue", ->
        opts    = update : (->)
        now     = moment().valueOf()
        cache   = new Psha(opts)

        p1      = createPending(  [1..5], now - _300ms) # +5
        p2      = createPending([11..20], now - _250ms) # +10
        p3      = createPending([31..60], now - _100ms) # +0
        p4      = createPending([11..15], now - _100ms) # +0

        pending = createPendingLookup(_.flatten([p1, p2, p3, p4]))

        # Should consider everything with age > 200ms as timedout
        cache._clearOverdueRequests(pending, _200ms)

        expect(cache.getPendingKeys()).to.have.length(p3.length + p4.length)


#    it.skip "if the request times out then all request sets waiting on the keys need to fail", ->
      # At the moment this doesn't need to be implemented because eventually those
      # pending requests will timeout, it's just a matter of time.

      # The idea behind this test case is to see that the timeout fails, and it will naturally
      # do so, just not immediately.

#    it.skip "if a request times out all other requests with pending keys in that request should also timeout", ->
      # At the moment this doesn't need to be implemented because eventually those
      # pending requests will timeout, it's just a matter of time.

      # The idea behind this test case is to see that the timeout fails, and it will naturally
      # do so, just not immediately.

    it "should timeout any late requests and callback with a timeout error", (done) ->
      opts = update: (->), timeout: 100
      cache = new Psha(opts, minTimeout: 100, timeoutInterval: 100)
      cache.get([1], (err, res) ->
        expect(res).to.not.exist
        expect(err).to.exist
        done()
      )

    it "should throw an error if timeout is less than 1sec", ->
      opts = update: (->), timeout: 100
      expect(-> new Psha(opts)).to.throw(Error)

    it "should throw an error if timeout doesn't exist", ->
      opts = update: (->), timeout: " non-number "
      expect(-> new Psha(opts)).to.throw(Error)


  describe 'basic get() calls =>', ->

    it 'should return items it has in cache', (done) ->
      opts  = update: ->
      ids   = makeIdCache([1...10])
      cache = new Psha(opts).fillCache(ids)

      req     = makeIdCache([1..2])
      keys    = _.keys(req)
      values  = _.values(req)

      cache.get(keys, (err, res) ->
        expect(err).to.not.exist
        expect(res).to.have.length(keys.length)
        for f in res
          expect(f in values, "didn't find #{f} in results").to.be.true
        done()
      )

    it 'should return items it has in cache without making requests if all keys are hits', (done) ->
      opts    = update: sinon.spy()
      cache   = new Psha(opts).fillCache(makeIdCache([1...10]))
      req     = makeIdCache([1..2])
      keys    = _.keys(req)

      cache.get(keys, (err, res) ->
        expect(err).to.not.exist
        expect(opts.update).to.not.have.been.called
        done()
      )


  describe 'cache hit/misses =>', ->

    it 'should only request keys that are cache misses', (done) ->
      ids     = makeIdCache([1..10])
      newIds  = _.keys(makeIdCache([8..12]))

      opts = update: (keys, cb) ->
        misses = makeIdCache([11..12])

        expect(keys).to.have.length(_.keys(misses).length)
        expect(_.all(keys, (id) -> misses[id]?)).to.be.true

        cb(null, misses)

      cache = new Psha(opts).fillCache(ids)
      cache.get(newIds, (err, pairs) -> done())

    it 'when the cache is empty a single key should be request via the update function', (done) ->
      opts = update: update(1)
      cache = new Psha(opts)
      cache.get(1, (err, pairs) -> done())

    it 'when the cache is empty all keys should be request via the update function', (done) ->
      ids = [1...10]
      opts = update: update(ids.length)
      cache = new Psha(opts)
      cache.get(ids, (err, pairs) -> done())

    it 'after fillCache is called the cache should no longer be empty', ->
      ids = makeIdCache([1...10])
      opts = update: ->
      cache = new Psha(opts).fillCache(ids)
      expect(cache.isEmpty()).to.be.false

    it 'fillCache should throw an error if the data is not an object', ->
      ids = [1...10]
      opts = update: ->
      cache = new Psha(opts)
      expect(-> cache.fillCache(ids)).to.throw(Error)


  describe 'check initial instantiation =>', ->

    it 'constructor should fail if not provided an update() method', ->
      expect(-> new Psha()).to.throw(Error)

    it 'constructor should work if provided an update() method', ->
      opts = update: ->
      expect(new Psha(opts)).to.be.ok

    it 'constructor should adjust ttl if provided', ->
      _60sec = 60*1000
      opts = update: (->), ttl: _60sec
      cache = new Psha(opts)
      expect(cache.getTtl()).to.be.ok
      expect(cache.getTtl()).to.equal(_60sec)

    it 'constructor should default ttl if not provided', ->
      opts = update: ->
      cache = new Psha(opts)
      expect(cache.getTtl()).to.be.ok
      expect(cache.getTtl()).to.equal(Psha.defaults.ttl)

    it 'cache should start empty', ->
      opts = update: ->
      cache = new Psha(opts)
      expect(cache.isEmpty()).to.be.true

    it 'cache should start with zero pending requests', ->
      opts = update: ->
      cache = new Psha(opts)
      expect(cache.hasPendingRequests()).to.be.false

    it 'should default timeout', ->
      opts = update: ->
      cache = new Psha(opts)
      expect(cache.getTimeout()).to.be.ok
      expect(cache.getTimeout()).to.equal(Psha.defaults.timeout)

    it 'should accept a configured timeout', ->
      _60sec = 60*1000
      opts = update: (->), timeout: _60sec
      cache = new Psha(opts)
      expect(cache.getTimeout()).to.be.ok
      expect(cache.getTimeout()).to.equal(_60sec)

    it "should default a logger if one isn't provided", ->
      opts = update: (->)
      cache = new Psha(opts)
      expect(cache.hasLogger()).to.be.true
      expect(cache.getLogger()).to.be.ok

    it "if a logger is provided it should use that logger", ->
      logger = (->
        log = console.log
        info  : (args...) ->
          log(args...)
        debug : (args...) ->
          log(args...)
        warn  : (args...) ->
          log(args...)
        error : (args...) ->
          log(args...))()

      opts =
        update: (->),
        logger: logger

      cache = new Psha(opts)
      expect(cache.hasLogger()).to.be.true
      expect(cache.getLogger()).to.equal(logger)

    it "should have saved the instance of a new cache in runningCaches for a new instance.", ->
      opts = update: ->
      cache = new Psha(opts)
      expect(Psha.runningCaches).to.have.length.above(1)

    it "should have saved the instance of a new cache in runningCaches for a new instance.", ->
      opts = update: ->
      cache = new Psha(opts)
      currentCache = _.first(_.filter(Psha.runningCaches, (r) -> r is cache))

      expect(currentCache).to.be.ok
      expect(currentCache).to.equal(cache)


  describe 'check setup =>', ->
    it 'should have found Psha', ->
      expect(Psha).to.be.ok
