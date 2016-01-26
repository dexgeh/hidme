#!node_modules/coffee-script/bin/coffee

http = require 'http'
https = require 'https'
fs = require 'fs'
crypto = require 'crypto'
url = require 'url'

tough = require 'tough-cookie'
validator = require 'valid-url'
htmlparser2 = require 'htmlparser2'
domutils = require 'domutils'

config =
  session:
    key_length: 16
    expire_timeout: 30 * 60 * 1000
  server:
    port: 8080

# logging
log = ->
  console.log "[#{new Date().toISOString()}] #{arguments[0]} #{
    Array.prototype.slice.call(arguments, 1).join(' ')}"

ERROR = log.bind null, "ERROR"
INFO  = log.bind null, "INFO "
DEBUG = log.bind null, "DEBUG"
TRACE = log.bind null, "TRACE"

# response helpers
http.ServerResponse.prototype.error = (error) ->
  ERROR error.message
  ERROR error.stack
  @writeHead 500
  @end()
http.ServerResponse.prototype.notFound = ->
  @writeHead 404
  @end()
http.ServerResponse.prototype.page = (name) ->
  fs.readFile name, 'utf8', (error, content) =>
    if error
      @error error
    else
      @writeHead 200,
        'content-type':'text/html; charset=utf8'
      @end content

# session management
class Session
  constructor: (@id, @expireTimeout, @data={}) ->
    @lastActivity = Date.now()
  expired: ->
    Date.now() - @lastActivity - @expireTimeout > 0
  get: (key) ->
    @lastActivity = Date.now()
    @data[key]
  set: (key, value) ->
    @lastActivity = Date.now()
    @data[key] = value

# interface
class SessionManager
  constructor: ->
  persist: (session, callback) ->
  retrieve: (id, callback) ->
  create: (callback) ->
  retrieveFromRequest: (req, callback) ->
    if not req.headers.cookie
      callback null
    else
      cookies = if req.headers.cookie instanceof Array
        req.headers.cookie.map (h) ->
          tough.Cookie.parse h,
            loose: yes
      else
        [
          tough.Cookie.parse req.headers.cookie,
            loose: yes
        ]
      for cookie in cookies
        if cookie.key is 'sessionId'
          return @retrieve cookie.value, callback
      callback null
  requestHandler: (req, res, callback) ->
    writeHead = res.writeHead
    res.writeHead = (statusCode, reason, obj) ->
      headers = if typeof reason is 'string'
        obj
      else
        reason
      if not headers
        headers = {}
      headers['set-cookie'] = "sessionId=#{req.session.id}"
      if typeof reason is 'string'
        writeHead.call res, statusCode, reason, headers
      else
        writeHead.call res, statusCode, headers
    end = res.end
    withSession = (session, callback) =>
      res.end = =>
        end.apply res, arguments
        @persist session, (error) -> ERROR error.message, error.stack if error
      callback()
    @retrieveFromRequest req, (error, session) =>
      if error
        res.error error
      else if session
        req.session = session
        withSession session, -> callback()
      else
        @create (error, session) ->
          if error
            res.error error
          else
            req.session = session
            withSession session, -> callback()

# in-memory session manager

class InMemorySessionManager extends SessionManager
  constructor: (@sessions={}) ->
  persist: (session, callback) ->
    @sessions[session.id] = session
    callback null
  retrieve: (id, callback) ->
    if @sessions[id] and not @sessions[id].expired()
      callback null, @sessions[id]
    else
      @sessions[id] = null
      callback null
  create: (callback) ->
    crypto.randomBytes config.session.key_length, (error, buffer) =>
      return callback error if error
      id = buffer.toString 'base64'
      session = new Session id, config.session.expire_timeout
      @sessions[id] = session
      callback null, session

sessionManager = new InMemorySessionManager

# utils

printRequestMetaData = (method, url, headers) ->
  TRACE "#{method} #{url}\n".concat ("#{k}: #{v}\n" for k,v of headers).join ""

printResponseMetaData = (statusCode, headers) ->
  TRACE "Status code: #{statusCode}\n".concat ("#{k}: #{v}\n" for k,v of headers).join ""

# proxy logic

filterRequestHeaders = (req, resource) ->
  headers = {}
  for k,v of req.headers
    if k is 'cookie'
      # skip: it has to be only sessionId
    else if k is 'referer' or k is 'referrer'
      headers[k] = resource
    else
      headers[k] = v
  if not req.session.cookieJar
    store = new tough.MemoryCookieStore
      synchronous: yes
    req.session.cookieJar = new tough.CookieJar store,
      looseMode: yes
  cookies = req.session.cookieJar.getCookiesSync resource
  if cookies.length > 0
    headers['cookie'] = cookies.join '; '
  headers

filterResponseHeaders = (req, clres, resource) ->
  headers = {}
  for k,v of clres.headers
    if k is 'location'
      headers[k] = new Buffer(v).toString 'base64'
    else if k is 'set-cookie'
      if typeof v is 'string'
        DEBUG "adding cookie to jar: #{v}"
        req.session.cookieJar.setCookieSync v, resource
      else
        v.map (s) ->
          DEBUG "adding cookie to jar: #{s}"
          req.session.cookieJar.setCookieSync s, resource
    else
      headers[k] = v
  headers

isHtml = (headers) ->
  headers['content-type'] and 0 == headers['content-type'].indexOf 'text/html'

fixedInjection = fs.readFileSync 'inject.html', 'utf8'
fixedInjectionWithLeadingHead = "<head>#{fixedInjection}"

attributesToMangle = [
  'a','href'
  'img','src'
  'link','href'
  'script','src'
  'form','action'
]

mangleBody = (body, resource, callback) ->
  body = body.toString 'binary'
  if /<head>/i.test body
    body = body.replace /<head>/i, fixedInjectionWithLeadingHead
  else if /^<!doctype/i.test body
    p = body.indexOf '>'
    body = "#{body.substring 0, p+1}#{fixedInjection}#{body.substring p+1}"
  else
    body = "#{fixedInjection}#{body}"
  parser = new htmlparser2.Parser new htmlparser2.DomHandler (error, dom) ->
    return callback error if error
    TRACE "parsed, working with dom"
    domutils.find (elem) ->
      if elem.type is 'tag'
          for e,i in attributesToMangle by 2
            [name, attr] = attributesToMangle[ i .. i+1 ]
            if elem.name is name and elem.attribs[attr]
              continue if elem.attribs[attr].match /^javascript:/i
              link = url.resolve resource, elem.attribs[attr]
              elem.attribs[attr] = new Buffer(link).toString 'base64'
              return no
      no # do not collect anything from the loop, it is modifying the dom
    , dom, yes
    body = domutils.getOuterHTML dom
    callback null, body
  parser.write body
  parser.done()

proxyRequest = (req, res) ->
  resource = req.url.substring 1
  resource = new Buffer(resource, 'base64').toString 'utf8'
  INFO resource
  # printRequestMetaData req.method, resource, req.headers
  reqOpts = url.parse resource
  reqOpts.method = req.method
  requester = if reqOpts.protocol is 'http:'
    http
  else if reqOpts.protocol is 'https:'
    https
  else
    null
  if requester is null
    return res.error 'unsupported protocol'
  reqOpts.rejectUnauthorized = no
  headers = filterRequestHeaders req, resource
  # printRequestMetaData req.method, resource, headers
  clreq = requester.request reqOpts, (clres) ->
    # printResponseMetaData clres.statusCode, clres.headers
    headers = filterResponseHeaders req, clres, resource
    # printResponseMetaData clres.statusCode, headers
    if isHtml headers
      delete headers['content-length']
      #capture body to mangle
      chunks = []
      clres.on 'data', chunks.push.bind chunks
      clres.on 'end', ->
        body = Buffer.concat chunks
        mangleBody body, resource, (error, body) ->
          return res.error error if error
          TRACE "got body to serve"
          res.writeHead clres.statusCode, headers
          res.end body
    else
      res.writeHead clres.statusCode, headers
      clres.on 'data', res.write.bind res
      clres.on 'ebd', res.end.bind res
    clreq.on 'error', res.error.bind res
  req.on 'data', (chunk) -> clreq.write chunk
  req.on 'end', clreq.end.bind clreq

# server and routing

isProxiedRequest = (url) ->
  try
    resource = url.substring 1
    resource = new Buffer(resource, 'base64').toString 'utf8'
    validator.isUri resource
  catch e
    false

server = http.createServer (req, res) ->
  sessionManager.requestHandler req, res, ->
    INFO req.url
    if req.url is '/' and req.method is 'GET'
      res.page 'index.html'
    else if isProxiedRequest req.url
      proxyRequest req, res
    else
      res.notFound()

server.listen config.server.port, ->
  TRACE "listening on port", config.server.port

