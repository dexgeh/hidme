
http = require 'http'

config = require './config'

server = http.createServer (req, res) ->
  res.writeHead 200,
    'Content-Type' : 'text/plain; charset=UTF-8'
  res.write "#{req.method} #{req.url} HTTP/1.1\n"
  for name,value of req.headers
    res.write "#{name}: #{value}\n"
  res.write "\n"
  req.on 'data', (c) -> res.write c
  req.on 'end', -> res.end()

server.listen config.echo.port, config.echo.host, ->
  console.log "echo listening on", config.echo.host, config.echo.port

