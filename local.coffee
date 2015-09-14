http = require 'http'
url  = require 'url'
zlib = require 'zlib'

config = require './config'

padding = null
if config.protocol.padSize
  padding = new Buffer config.protocol.padSize
  for i in [0..config.protocol.padSize]
    c = 32 + Math.random() * (128 - 32)
    padding.write String.fromCharCode(c), 1, 1, 'ascii'

encodeDestination = (destination, callback) ->
  jsonString = JSON.stringify destination
  zlib.gzip new Buffer(jsonString), (err, zipped) ->
    return callback err if err
    callback null, zipped.toString 'base64'

send = (res, status) ->
  res.writeHead status
  res.end()

server = http.createServer (req, res) ->
  destination = url.parse req.url
  destination.method = req.method
  destination.headers = req.headers
  destination.host = req.headers['host']
  destination.hostname = req.headers['host']
  encodeDestination destination, (err, encodedDestination) ->
    return send res, 500 if err
    options =
      method : "POST"
      host : config.remote.host
      port : config.remote.port
      path : config.protocol.endpoint
      headers :
        host : config.remote.host
    options.headers[config.protocol.header] = encodedDestination
    if config.proxy
      options.host = config.proxy.host
      options.port = config.proxy.port
      options.path = "http://#{config.remote.host}:" +
        "#{config.remote.port}#{options.path}"
      options.headers.host = "#{config.remote.host}:" +
        "#{config.remote.port}"
    proxyReq = http.request options, (proxyRes) ->
      res.writeHead proxyRes.statusCode, proxyRes.headers
      padSize = config.protocol.padSize or 0
      proxyRes.on 'data', (c) ->
        if padSize
          if c.length <= padSize
            padSize -= c.length
            return
          else
            c = c.slice padSize, c.length
            padSize = 0
        res.write c
      proxyRes.on 'end', -> res.end()
    if config.protocol.padSize
      proxyReq.write padding
    req.on 'data', (c) -> proxyReq.write c
    req.on 'end', -> proxyReq.end()

server.listen config.local.port, config.local.host, ->
  console.log "local listening on", config.local.host, config.local.port


