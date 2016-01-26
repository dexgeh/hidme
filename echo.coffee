#!node_modules/coffee-script/bin/coffee

http = require 'http'

pageStart = (req) ->
  """<!doctype html>
  <html>
    <head>
      <title>echo</title>
    </head>
    <body>
      <div>
        <p>tests</p>
        <a href=http://www.google.com/>link</a>
        <img src=http://www.google.com/favicon.ico>
        <form action=echo>
          <input type=hidden name=aField value=aValue>
          <select onchange='document.forms[0].method=this.value; document.forms[0].submit()'>
            <option></option>
            <option>GET</option>
            <option>POST</option>
          </select>
        </form>
      </div>

      <pre>#{req.method} #{req.url} HTTP/1.1

      """

server = http.createServer (req,res) ->
  if req.url is '/echo'
    res.writeHead 200,
      'content-type' : 'text/html; charset=utf8'
    res.write pageStart req
    for k,v of req.headers
      res.write "#{k}: #{v}\n"
    res.write '\n'
    req.on 'data', (d) ->
      res.write d
    req.on 'end', ->
      res.end "</pre></body></html>"
  else if req.url is '/redirect'
    res.writeHead 302,
      location: '/echo'
    res.end()

server.listen 12345
console.log 'listening on http://localhost:12345/'

