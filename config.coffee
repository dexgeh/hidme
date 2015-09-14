module.exports =
  protocol :
    padSize : 1024
    endpoint : '/p'
    header : 'cookie'
  remote :
    host : 'localhost'
    port : 8080
  local :
    host : 'localhost'
    port : 8081
  proxy :
    host : 'localhost'
    port : 8082
  echo :
    host : 'localhost'
    port : 8083


