#!/usr/bin/env node
inteval = 2000
blocked_room_name = /((?=.+?[群号战队收人纳招募].+?)(.*?[群号战队收人纳招募]*?.*?[⒈⒉⒊⒋⒌⒍⒎⒏⒐⑴⑵⑶⑷⑸⑹⑺⑻⑼①②③④⑤⑥⑦⑧⑨㈠㈡㈢㈣㈤㈥㈦㈧㈨一二三四五六七八九零壹贰叁肆伍陆柒捌玖〇\d].*?[群号战队收人纳招募]*?.*?){8,})|(?!(([群号战队收人纳招募]).*?\4))([群号战队收人纳招募].*?[群号战队收人纳招募])/

_ = require 'underscore'
config = require 'yaml-config'
request = require 'request'
WebSocketServer = require('websocket').server
http = require 'http'
https = require 'https'
fs = require 'fs'

Iconv = require('iconv').Iconv
gbk_to_utf8 = new Iconv 'GBK', 'UTF-8//TRANSLIT//IGNORE'

settings = config.readConfig process.cwd() + '/' + "config.yaml"
console.log settings

clients = []

server = http.createServer (request, response)->
  response.writeHead(200, {'Content-Type': 'application/json'});
  response.end(JSON.stringify(_.flatten(_.pluck(settings.servers, 'rooms'))), 'utf8')
server_secure = https.createServer
    key: fs.readFileSync(settings.ssl_certificate_key)
    cert: fs.readFileSync(settings.ssl_certificate)
  , (request, response)->
    response.writeHead(200, {'Content-Type': 'application/json'});
    response.end(JSON.stringify(_.flatten(_.pluck(settings.servers, 'rooms'))), 'utf8')


fs.unlink settings.listen, (err)->
  process.umask(0);
  server.listen settings.listen, ->
    console.log('Server is listening on ' + settings.listen)
server_secure.listen settings.listen_secure, ->
  console.log('Server is listening on ' + settings.listen_secure)

originIsAllowed = (origin)->
  return true

handle = (request)->
  if (!originIsAllowed(request.origin))
    request.reject()
    console.log((new Date()) + ' Connection from origin ' + request.origin + ' rejected.')
    return

  connection = request.accept(null, request.origin)
  clients.push(connection)
  console.log((new Date()) + ' Connection accepted.')
  connection.sendUTF JSON.stringify _.flatten _.pluck(settings.servers, 'rooms'), true

  connection.on 'close', (reasonCode, description)->
    console.log("#{new Date()} Peer #{connection.remoteAddress} disconnected: #{description}")
    index = clients.indexOf(connection)
    clients.splice(index, 1) unless index == -1

new WebSocketServer(
  httpServer: server
  autoAcceptConnections: false
).on 'request', handle

new WebSocketServer(
  httpServer: server_secure
  autoAcceptConnections: false
).on 'request', handle

main = (servers)->
  _.each servers, (server)->
    request {url: server.index + '/?operation=getroomjson', timeout: inteval, encoding: (if server.encoding == 'GBK' then 'binary' else 'utf8'), json: server.encoding != 'GBK'}, (error, response, body)->
      if error
        console.log error
      else
        try
          body = JSON.parse gbk_to_utf8.convert(new Buffer(body, 'binary')).toString() if server.encoding == 'GBK'
          refresh(server, body)
        catch e
          console.log e.stack, error, response, body

send = (data)->
  data = JSON.stringify data
  for client in clients
    client.sendUTF data

refresh = (server, data)->
  rooms = (parse_room(server, room) for room in data.rooms )
  rooms = _.reject rooms, (room)->
    if room.name.match blocked_room_name
      console.log "blocked: #{room.name}"
      return true
    for user in room.users
      if user.name.match blocked_room_name
        console.log "blocked: #{room.name} because user #{user.name}"
        return true
    false
  rooms_changed = (room for room in rooms when !_.isEqual room, _.find server.rooms, (r)->
    r.id == room.id).concat ((room._deleted = true; room) for room in server.rooms when _.all rooms, (r)->
    (r.id != room.id))
  if rooms_changed.length
    send rooms_changed
    server.rooms = rooms
  console.log server.name, rooms_changed.length

parse_room = (server, data)->
  #struct HostInfo {
  #  unsigned int lflist;
  #  unsigned char rule;
  #  unsigned char mode;
  #  bool enable_priority;
  #  bool no_check_deck;
  #  bool no_shuffle_deck;
  #  unsigned int start_lp;
  #  unsigned char start_hand;
  #  unsigned char draw_count;
  #  unsigned short time_limit;
  #};
  matched = data.roomname.match /^(P)?(M)?(T)?\#?(.*)$/
  result = {
  id: String.fromCharCode('A'.charCodeAt() + server.id) + data.roomid,
  name: matched[4],
  status: data.istart
  server_id: server.id

  #pvp: matched[1]?
  #private: data.needpass == "true",

  #lflist: 0,
  #rule: 0,
  #mode: matched[2] ? matched[3] ? 2 : 1 : 0,
  #enable_priority: false,
  #no_check_deck: false,
  #no_shuffle_deck: false,
  #start_lp: 8000,
  #start_hand: => 5,
  #draw_count: => 1,
  #time_limit: => 0,

  users: []
  }
  for user_data in data.users
    user = parse_user(server, user_data)
    if (user.player == 7) or !_.some(result.users, (existed_user) ->
      existed_user.player == user.player)
      result.users.push user

  result.pvp = true if matched[1]
  result['private'] = true if data.needpass == "true"

  if matched[2]
    result.mode = 1
  else if matched[3]
    result.mode = 2
  else if matched = result.name.match /^(\d)(\d)(F)(F)(F)(\d+),(\d+),(\d+),(.*)$/
    result.name = matched[9]

    result.rule = parseInt matched[1]
    result.mode = parseInt matched[2]
    #enable_priority: false,
    #no_check_deck: false,
    #no_shuffle_deck: false,
    result.start_lp = parseInt matched[6]
    result.start_hand = parseInt matched[7]
    result.draw_count = parseInt matched[8]

  result

#define NETPLAYER_TYPE_PLAYER1 0
#define NETPLAYER_TYPE_PLAYER2 1
#define NETPLAYER_TYPE_PLAYER3 2
#define NETPLAYER_TYPE_PLAYER4 3
#define NETPLAYER_TYPE_PLAYER5 4
#define NETPLAYER_TYPE_PLAYER6 5
#define NETPLAYER_TYPE_OBSERVER 7

parse_user = (server, data)->
  {
  id: data.name,
  name: data.name,
  #nickname: data.name,
  certified: data.id == "-1",
  player: data.pos & 0xf
  }

init = (servers)->
  for s in servers
    s.rooms = []
  main servers
  setInterval ->
    main servers
  , inteval

if typeof settings.servers == "string"
  request settings.servers, (error, response, body)->
    settings.servers = JSON.parse body
    init settings.servers
else
  init settings.servers


