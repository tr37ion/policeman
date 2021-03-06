

{ windows } = require 'windows'
{ tabs } = require 'tabs'

{ prefs } = require 'prefs'


prefs.define REQUEST_PER_TAB_LIMIT_PREF = 'requestMemo.requestPerTabLimit',
  default: 2000
  get: (n) -> Math.max 200, n


###
Remembers requests attempted by each tab with corresponding decisions
(for later use by ui/popup).
###
exports.memo = memo = new class
  class Stats
    constructor: ->
      @allowHits = 0
      @rejectHits = 0
    hit: (origin, destination, context, decision) ->
      if decision
        @allowHits += 1
      else
        @rejectHits += 1

  # tabId -> array of 4-arrays [origin, dest, context, decision]
  _tabIdToRequests: Object.create null

  # tabId -> Stats
  _tabIdToStats: Object.create null
  _contentWindowToStats: new WeakMap

  _addRequestByTab: (i, origin, dest, context, decision) ->
    for prop in ['nodeName', 'className', 'id']
      # Force these property getters for later use by UI if the node goes dead
      context[prop]
    requests = @_tabIdToRequests[i]
    requests.push [origin, dest, context, decision]
    requests.shift() if requests.length > @_requestPerTabLimit
    @_tabIdToStats[i].hit origin, dest, context, decision

  _resetTab: (i) ->
    @_tabIdToRequests[i] = []
    @_tabIdToStats[i] = new Stats

  _requestPerTabLimit: prefs.get REQUEST_PER_TAB_LIMIT_PREF


  constructor: ->
    tabs.onClose.add @removeRequestsMadeByTab.bind @

    prefs.onChange REQUEST_PER_TAB_LIMIT_PREF, (n) => @_requestPerTabLimit = n

  removeRequestsMadeByTab: (tab) ->
    tabId = tabs.getTabId tab
    delete @_tabIdToRequests[tabId]
    delete @_tabIdToStats[tabId]

  add: ([origin, dest, context], decision) ->
    i = context._tabId
    return if not i
    if context.contentType == 'DOCUMENT' \
    and context.hints.navigation \
    and not ( # conditions for no real page reload follow
      dest.scheme == 'javascript' \ # href="javascript:..."
      or origin.spec == dest.spec   # href="#hash"
    )
      # Page reload or navigated to another document, reset the data
      @_resetTab i
      # Not to record the document request itself seems reasonable
      return
    unless i of @_tabIdToRequests
      @_resetTab i
    @_addRequestByTab i, origin, dest, context, decision

  getByTabId: (tabId) ->
    return @_tabIdToRequests[tabId] or []
  getStatsByTabId: (tabId) ->
    return @_tabIdToStats[tabId] or new Stats

  getByTab: (tab) ->
    return @getByTabId tabs.getTabId tab
  getStatsByTab: (tab) ->
    return @getStatsByTabId tabs.getTabId tab

  getByWindow: (win) ->
    [].concat (@getByTabId tabs.getTabId tab for tab in win.gBrowser.tabs)...

  getAll: ->
    [].concat (quads for tab, quads of _tabIdToRequests)...


