
http = require 'http'

require './remote'
require './local'
require './echo'
require './proxy'

config = require './config'

test = (method, data) ->
  options =
    hostname : config.local.host
    port : config.local.port
    path : "http://#{config.echo.host}:#{config.echo.port}/"
    headers :
      host : "#{config.echo.host}:#{config.echo.port}"
    method : method
  console.log "request", options
  req = http.request options, (res) ->
    console.log "got response", res.statusCode, res.headers
    res.on 'data', (c) ->
      console.log "got data", c.toString 'ascii'
  if data
    req.write data
  req.end()


setTimeout ->
  test "GET"
  test "POST", "post data"
, 200
