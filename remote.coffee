http = require 'http'
zlib = require 'zlib'

config = require './config'

padding = null
if config.protocol.padSize
  padding = new Buffer config.protocol.padSize
  for i in [0..config.protocol.padSize]
    c = 32 + Math.random() * (128 - 32)
    padding.write String.fromCharCode(c), 1, 1, 'ascii'

send = (res, status) ->
  res.writeHead status
  res.end()

decodeDestination = (destination, callback) ->
  zipped = new Buffer destination, 'base64'
  zlib.gunzip zipped, (error, jsonString) ->
    return callback error if error
    try
      callback null, JSON.parse jsonString
    catch e
      callback e

fixDestinationHost = (destination) ->
  m = destination.host.match /^(.*):\d+$/
  if m
    destination.host = m[1]
    destination.hostname = m[1]
  destination


server = http.createServer (req, res) ->
  if req.method isnt 'POST'
    send res, 405
  if req.url isnt config.protocol.endpoint
    send res, 404
  destHVal = req.headers[config.protocol.header]
  decodeDestination destHVal, (err, destination) ->
    return send res, 500 if err
    destination = fixDestinationHost destination
    proxyReq = http.request destination, (proxyRes) ->
      res.writeHead proxyRes.statusCode, proxyRes.headers
      if padding
        res.write padding
      proxyRes.on 'data', (c) -> res.write c
      proxyRes.on 'end', -> res.end()
    proxyReq.flushHeaders()
    padSize = config.protocol.padSize || 0
    req.on 'data', (c) ->
      if padSize
        if c.length <= padSize
          padSize -= c.length
          return
        else
          c = c.slice padSize, c.length
          padSize = 0
      proxyReq.write c
    req.on 'end', -> proxyReq.end()

server.listen config.remote.port, config.remote.host, ->
  console.log "remote listening on", config.remote.host, config.remote.port


