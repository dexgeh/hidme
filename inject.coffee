
_hidme =
  injections: []
  args: (a) -> Array.prototype.slice.call a
  b64safe : (s) ->
    btoa encodeURIComponent(s).replace /%([0-9A-F]{2})/g, (m,p1) ->
      String.fromCharCode "0x#{p1}"
  XMLHttpRequest :
    original_constructor : XMLHttpRequest.prototype.constructor
    constructor: ->
      url = arguments[1]
      url = _hidme.b64safe url
      args = _hidme.args arguments
      args[1] = url
      @original_constructor.apply null, args
    injection: ->
      XMLHttpRequest.prototype.constructor = @constructor

for k,v of _hidme
  if v.injection
    v.injection()

