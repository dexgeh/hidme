http = require 'http'
url  = require 'url'

config = require './config'

server = http.createServer (req, res) ->
  options = url.parse req.url
  options.method = req.method
  options.headers = req.headers
  m = req.headers['host'].match /^(.*):\d+$/
  if m
    options.host = m[1]
    options.hostname = m[1]
  else
    options.host = req.headers['host']
    options.hostname = req.headers['host']
  proxyReq = http.request options, (proxyRes) ->
    res.writeHead proxyRes.statusCode, proxyRes.headers
    proxyRes.on 'data', (c) -> res.write c
    proxyRes.on 'end', -> res.end()
  req.on 'data', (c) -> proxyReq.write c
  req.on 'end', -> proxyReq.end()

server.listen config.proxy.port, config.proxy.host, ->
  console.log "proxy listening on", config.proxy.host, config.proxy.port

