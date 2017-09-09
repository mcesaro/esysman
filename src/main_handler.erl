%% Copyright (c) 2012, Wes James <comptekki@gmail.com>
%% All rights reserve.
%% 
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions are met:
%% 
%%     * Redistributions of source code must retain the above copyright
%%       notice, this list of conditions and the following disclaimer.
%%     * Redistributions in binary form must reproduce the above copyright
%%       notice, this list of conditions and the following disclaimer in the
%%       documentation and/or other materials provided with the distribution.
%%     * Neither the name of "ESysMan" nor the names of its contributors may be
%%       used to endorse or promote products derived from this software without
%%       specific prior written permission.
%% 
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
%% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
%% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
%% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
%% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
%% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
%% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
%% POSSIBILITY OF SUCH DAMAGE.
%% 
%%

-module(main_handler).

-export([init/2]).

-include("esysman.hrl").

%%

init(Req, Opts) ->
		case fire_wall(Req) of
			allow ->
				Creds=login_is(),
				case is_list(Creds) of
					true -> 
						{Cred, Req2} = checkCreds(Creds, Req, Opts),
						case Cred of
							fail ->
								app_login(Req2, Opts);
							pass ->
								app_front_end(Req2, Opts)
						end;
					false -> 
						case Creds of
							off ->
								app_front_end(Req, Opts);
							_  ->
								app_login(Req, Opts)
						end
				end;
			deny ->
				fwDenyMessage(Req, Opts)
		end.

%%

fire_wall(Req) ->	
	{PeerAddress, _Port} = cowboy_req:peer(Req),
	{{Year, Month, Day}, {Hour, Minute, Second}} = calendar:local_time(),
	Date = lists:flatten(io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w",[Year,Month,Day,Hour,Minute,Second])),
	{ok, [_,{FireWallOnOff,IPAddresses},_,_]}=file:consult(?CONF),
	case FireWallOnOff of
		on ->
			case lists:member(PeerAddress,IPAddresses) of
				true ->
					io:format("~ndate: ~p -> firewall allow -> ~p",[Date, PeerAddress]),
					allow;
				false ->
					io:format("~ndate: ~p -> firewall denied -> ~p",[Date, PeerAddress]),
					deny
			end;
		off ->
			allow
	end.

%%

login_is() ->
	{ok, [_,_,{UPOnOff,UnamePasswds},_]}=file:consult(?CONF),
	case UPOnOff of
		on ->
			UnamePasswds;
		off ->
			off
	end.
	
%%

checkCreds(UnamePasswds, Req, _Opts) ->
	[{Uname,_}] = UnamePasswds,
	Cookies = cowboy_req:parse_cookies(Req),
    case (Cookies == undefined) or (Cookies == []) of
		true ->
			checkPost(UnamePasswds, Req);
		false  ->
			CookieVal = get_cookie_val(), 
			Req2 = cowboy_req:set_resp_cookie(Uname, CookieVal, Req, #{max_age =>  ?MAXAGE, path => "/", secure => true, http_only => true}),
			{pass, Req2}
	end.

%%

checkCreds([{Uname,Passwd}|UnamePasswds], Uarg, Parg, Req) ->
    case Uname of
		Uarg ->
			case Passwd of
				Parg ->
					CookieVal = get_cookie_val(), 
					Req0 = cowboy_req:set_resp_cookie(Uname, CookieVal, Req, #{max_age =>  ?MAXAGE, path => "/", secure => true, http_only => true}),
					{pass, Req0};
				_ ->
					checkCreds(UnamePasswds,Uarg,Parg,Req)
			end;
		_ ->
			checkCreds(UnamePasswds, Uarg, Parg, Req)
	end;
checkCreds([], _Uarg, _Parg, Req) ->
	{fail, Req}.

%%

checkPost(UnamePasswds,Req) ->
	case cowboy_req:method(Req) of
		<<"POST">> ->
			{ok, FormData, Req2} = cowboy_req:read_urlencoded_body(Req),
			case FormData of
				[{_UnameVar, UnameVal}, {_PasswdVar, PasswdVal}, _Login] ->
					checkCreds(UnamePasswds, UnameVal, PasswdVal, Req2);
				_ ->
					{fail, Req}
			end;
		_ ->
			{fail, Req}
	end.

%%

get_cookie_val() ->
	list_to_binary(
	  integer_to_list(
		calendar:datetime_to_gregorian_seconds({date(), time()})
	   )).

%%

app_login(Req, Opts) ->

		case fire_wall(Req) of
			allow ->
				Req3 =
					case is_list(login_is()) of
						true ->
							cowboy_req:reply(
							  200,
							  #{ <<"content-type">> => <<"text/html">> },

<<"<html>
<head> 
<title>", ?TITLE, "</title>

<meta Http-Equiv='Cache-Control' Content='no-cache'>
<meta Http-Equiv='Pragma' Content='no-cache'>
<meta Http-Equiv='Expires' Content='0'>
<META HTTP-EQUIV='EXPIRES' CONTENT='Mon, 30 Apr 2012 00:00:01 GMT'>

<link rel='icon' href='/static/favicon.ico' type='image/x-icon' />
<link rel=\"stylesheet\" href=\"", ?CSS, "?", (now_bin())/binary, "\" type=\"text/css\" media=\"screen\" />
<script type='text/javascript' src='", ?JQUERY, "'></script>

<script>
$(document).ready(function(){

$('#uname').focus();

});
</script>
<style>
body {background-color:black; color:yellow}
</style>
</head>

<body>
<form action='/esysman' method='post'>
<div>
  <h3>", ?TITLE, " Login</h3>
</div>
<div class='unamed'>
  <div class='unamed-t'>Username: </div><div><input id='uname' type='text' name='uname'></div>
</div>
<div class='passwdd'>
  <div class='passwdd-t'>Password: </div><div><input id='passwd' type='password' name='passwd'></div>
</div>
<div class='logind'>
  <div class='fl'><input type='submit' name='login' value='Login'></div>
</div>
</form>


</body>
</html>">>, Req);


						false ->
							{ok, cowboy_req:reply(
							  200, 
							  #{ <<"Content-Type">> => <<"text/html">> },
<<"<html>
<head> 
<title>", ?TITLE, " Login</title>

<meta Http-Equiv='Cache-Control' Content='no-cache'>
<meta Http-Equiv='Pragma' Content='no-cache'>
<meta Http-Equiv='Expires' Content='0'>
<META HTTP-EQUIV='EXPIRES' CONTENT='Mon, 30 Apr 2012 00:00:01 GMT'>

<link rel='icon' href='/static/favicon.ico' type='image/x-icon' />
</head>
<body>
hi
</body>
</html>">>, Req), Opts}
            end,
            {ok, Req3, Opts};
        deny ->
          fwDenyMessage(Req, Opts)
    end.

%%

fwDenyMessage(Req, Opts) ->

	Req2 = cowboy_req:reply(
			200,
			#{ <<"content-type">> => <<"text/html">> },

<<"<html>
<head> 
<title>", ?TITLE, "</title>

<meta Http-Equiv='Cache-Control' Content='no-cache'>
<meta Http-Equiv='Pragma' Content='no-cache'>
<meta Http-Equiv='Expires' Content='0'>
<META HTTP-EQUIV='EXPIRES' CONTENT='Mon, 30 Apr 2012 00:00:01 GMT'>

<link rel='icon' href='/static/favicon.ico' type='image/x-icon' />
<style>
body {background-color:black; color:yellow}
</style>
</head>
<body>
Access Denied!
</body>
</html>">>, Req),
    {ok, Req2, Opts}.

%%

app_front_end(Req, Opts) ->
	Host = cowboy_req:host(Req),

	PortInt  = cowboy_req:port(Req),
	Port = list_to_binary(integer_to_list(PortInt)),
	{{Year, Month, Day}, {Hour, Minute, Second}} = calendar:local_time(),
	Date = lists:flatten(io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w",[Year,Month,Day,Hour,Minute,Second])),
	io:format("~ndate: ~p -> host: ~p : ~p~n", [Date, Host, Port]),

	Get_rms = get_rms_keys(?ROOMS, 49),

	{ok, [_, _, _, {Ref_cons_time}]} = file:consult(?CONF),

	Req2 = cowboy_req:reply(
			200,
			#{ <<"content-type">> => <<"text/html">> },

<<"<html>
<head> 
<title>", ?TITLE, "</title>

<meta Http-Equiv='Cache-Control' Content='no-cache'>
<meta Http-Equiv='Pragma' Content='no-cache'>
<meta Http-Equiv='Expires' Content='0'>
<META HTTP-EQUIV='EXPIRES' CONTENT='Mon, 30 Apr 2012 00:00:01 GMT'>

<link rel='icon' href='/static/favicon.ico' type='image/x-icon' />
<link rel=\"stylesheet\" href=\"", ?JQUERYUICSS, "?", (now_bin())/binary, "\" type=\"text/css\" media=\"screen\" />
<link rel=\"stylesheet\" href=\"", ?CSS, "?", (now_bin())/binary, "\" type=\"text/css\" media=\"screen\" />
<script type='text/javascript' src='", ?JQUERY, "'></script>
<script type='text/javascript' src='", ?JQUERYUI, "'></script>

<script>

$(document).ready(function(){

  if ('MozWebSocket' in window) {
	WebSocket = MozWebSocket;
  }

  if (!window.WebSocket){
	alert('WebSocket not supported by this browser')
  } else {  //The user has WebSockets

// websocket code from: http://net.tutsplus.com/tutorials/javascript-ajax/start-using-html5-websockets-today/

  var host=
'",
Host/binary,
"';
  var port='",
Port/binary,
"';

  var rall=false;
  var socket = 0;
  var ws_str = '';

	var r=false;
	rall=false;
	var first=true;
    var tot_cnt=0;
	var shutbox='';
    var retUsers='';

   function lockscr() {
      $('#lockpane').show();
      $('#lockpane').attr('tabindex', 1);
      $('#unlockscr').attr('tabindex', -1);

      $('#unlockscr').show();
      $('#unlockscr').focus();
      $('#unlockscrpasswd').val('');
      $('#unlockscrpasswd').hide();

      send('0:lockactivate:');
   }


  function wsconnect() {
        socket = new WebSocket(ws_str);
		message(true, socket.readyState);

		socket.onopen = function(){
		//	console.log('onopen called');
			send('client-connected');
			message(true, socket.readyState);
",
(init_open(?ROOMS))/binary,
(init2(?ROOMS,Ref_cons_time))/binary,
"

      if (",?AUTOLOCK,") {
        lockscr();
      }

	}

		socket.onmessage = function(m){
//			console.log('onmessage called');
			if (m.data)

				if(m.data.indexOf(':'>0) || m.data.indexOf('/')>0){
					if(m.data.indexOf(':')>0) {
						if(m.data.indexOf('^')>0) {
							boxCom2=m.data.split('^');
							boxCom = boxCom2[0].split(':');
							boxCom[2] = boxCom2[1];
							boxCom.push(boxCom2[2].slice(1));
						} else {
							boxCom=m.data.split(':');
						}
						sepcol=true;
					}
					else {
					   boxCom=m.data.split('/');
					   sepcol=false;
					}

					box=boxCom[0].substr(0,boxCom[0].indexOf('.'));					
					users='", ?IGNORESHOWUSERS, "';

					if (box.indexOf('@')>0)
					   box= box.split('@')[1]; //box.substr(box.indexOf('@')+1, box.length-1);
					switch(boxCom[1]) {
						case 'loggedon':
							if(users.indexOf(box)<0 && users.indexOf(boxCom[2])<0) {
								message(sepcol,boxCom[0] + ': ' + boxCom[2]);
							}
							else {
							  message(sepcol,boxCom[0] + ':');
						    }

							if (boxCom[2].indexOf('command not')<0)
                            {
								 if(boxCom[2].length>0)
                                 {
                                   if(chk_users('", ?IGNOREUSERS, "',boxCom[2]))
                                   {
									 if(users.indexOf(box)<0) {
										 $('#'+box+'status').html(retUsers);									
									 }
                                     else {
									   $('#'+box+'status').html('Up');									
                                     }
                                   }
                                   else
                                   {
                                     $('#'+box+'status').html('Up');
                                   }
                                 }
							     else
							         $('#'+box+'status').html('Up');
                              }
                              else {
                                 $('#'+box+'status').html('.');
							     $('#'+box+'status').css('color','red');
							     $('#'+box+'status').css('background-color','#550000');
                               }
							break;
						case 'pong':
							$('#'+box+'status').css('color','green');
							$('#'+box+'status').css('background-color','#005500');
							$('#'+box+'_hltd').css('background-color','#005555');
							$('#'+box+'_ltd').css('background-color','#005555');
							message(sepcol,boxCom[0] + ': ' + 'pong');
							break;
					    case 'pang':
							$('#'+box+'status').css('color','red');
							$('#'+box+'status').css('background-color','#550000');
							message(sepcol,boxCom[0] + ': ' + 'pang');
							break;
						case 'reboot':
							$('#'+box+'status').css('color','red');
							$('#'+box+'status').css('background-color','#550000');
                       		$('#'+box+'status').html('.');
							$('#'+box+'_hltd').css('background-color','#000000');
							$('#'+box+'_ltd').css('background-color','#000000');
							message(sepcol,boxCom[0] + ': ' + 'reboot');
							break;
					    case 'shutdown':
							$('#'+box+'status').css('color','red');
							$('#'+box+'status').css('background-color','#550000');
                       		$('#'+box+'status').html('.');
							$('#'+box+'_hltd').css('background-color','#000000');
							$('#'+box+'_ltd').css('background-color','#000000');
							message(sepcol,boxCom[0] + ': ' + 'shutdown');
							break;
					    case 'dffreeze':
							$('#'+box+'dfstatus').css('color','cyan');
							$('#'+box+'dfstatus').css('background-color','#006666');
							$('#'+box+'status').css('color','red');
							$('#'+box+'status').css('background-color','#550000');
                            				$('#'+box+'status').html('.');
							$('#'+box+'_hltd').css('background-color','#000000');
							$('#'+box+'_ltd').css('background-color','#000000');
							message(sepcol,boxCom[0] + ': ' + 'dffreeze');
							break;
					    case 'dfthaw':
							$('#'+box+'dfstatus').css('color','green');
							$('#'+box+'dfstatus').css('background-color','#006600');
							$('#'+box+'status').css('color','red');
							$('#'+box+'status').css('background-color','#550000');
                            				$('#'+box+'status').html('.');
							$('#'+box+'_hltd').css('background-color','#000000');
							$('#'+box+'_ltd').css('background-color','#000000');
							message(sepcol,boxCom[0] + ': ' + 'dfthaw');
							break;
					    case 'dfstatus':
							if(!(boxCom[2].indexOf('thawed'))){
								$('#'+box+'dfstatus').html('DF');
								$('#'+box+'dfstatus').css('color','green');
								$('#'+box+'dfstatus').css('background-color','#006600');
							}
							else {
								$('#'+box+'dfstatus').html('DF');
								$('#'+box+'dfstatus').css('color','cyan');
								$('#'+box+'dfstatus').css('background-color','#006666');
							}
							message(sepcol,boxCom[0] + ': ' + 'dfstatus');
							break;
					    case 'copy':
							$('#'+box+'status').css('color','#00cc00');
							$('#'+box+'status').css('background-color','#006600');
							message(sepcol,boxCom[0] + ': ' + 'copy');
							break;
                        case 'list_ups_dir':
						  $('#mngscrbox').html(boxCom[2]);
							message(sepcol,boxCom[0] + ': ' + 'list_ups_dir');
                           break;
                        case 'editscrfile':
                          var fname = $('#scrname').html().split('.');
                          if (fname[fname.length-1] == 'cmd') {
						    $('#scripttext').val(boxCom[2]);
                          } else {
                            notcmd = true;
                            $('#scrtxtbox').hide();
                          }
						  $('#scrdesc').val(boxCom[3].substring(1, boxCom[3].length-2));
							message(sepcol,boxCom[0] + ': ' + 'editscrfile');
                           break;
					    case 'com':
						    $('#'+box+'status').css('color','#00cc00');
							$('#'+box+'status').css('background-color','#006600');
							message(sepcol,boxCom[0] + ': ' + 'com');
							break;
					    default:
						    if(boxCom[2] != undefined) {
						        message(sepcol,boxCom[0] + ': <br>.....' + boxCom[1] + ' ' + boxCom[2] + '<br>' + m.data.replace(/\\n|\\r\\n|\\r/g, '<br>').replace(/->/g, '-> <br>'))
                            }
               			    else if(boxCom[1] == undefined) {
						        message(sepcol,boxCom[0]);
                            }
                   		    else {
                                if (boxCom[1].indexOf('<br>') > 0) {
                                  message(sepcol,boxCom[0] + ': <br>.....' + boxCom[1])
                                } else {
						          message(sepcol,boxCom[0] + ': ' + boxCom[1].replace(/\\n|\\r\\n|\\r/g, '<br>'))
                                }
                            }
					} // end switch

		            var ignore_sd = '",?IGNORESHUTDOWN,"';
                    var ignore_rb = '",?IGNOREREBOOT,"';
                    var ignoreu1 = '",?IGNOREU1,"';
                    var ignoreu2 = '",?IGNOREU2,"';
                    var ignoreu3 = '",?IGNOREU3,"';
                    var ignoreu4 = '",?IGNOREU4,"';

                    if (boxCom.length > 2) {
						 if(boxCom[2].indexOf('|') > -1 && boxCom[2].indexOf(ignoreu1) < 0 && 
								boxCom[2].indexOf(ignoreu2) < 0 && boxCom[2].indexOf(ignoreu3) < 0 &&
								boxCom[2].indexOf(ignoreu4) < 0
						   )
						   {
							  if (ignore_rb.indexOf(box) < 0 && box.length > 0) {
							     send(boxCom[0]+':reboot:0');
							  }
						   }
				    }

   					if (ignore_sd.indexOf(box) < 0 && box.length > 0)
                    {
					  if($('#shutdownTimerSwitch').val() == '1') {
                        if (hdiff(Number($('#shutdownTimeH').val()), Number($('#shutdownTimeH2').val()))) {
                          if (shutbox != box) {
	        			    send(boxCom[0]+':shutdown:0');
                            shutbox = box;
                          }
                        }
					  }
					}
				}
				else message(true,m.data)
		}

		socket.onclose = function() {
//			console.log('onclose called')
		    message(true,'Socket status: 3 (Closed)');
		}

		socket.onerror = function(e) {
			message(true,'Socket Status: '+e.data)
		}

  } // end function wsconnect()

  
   if(window.location.protocol == 'https:')
     ws_str='wss://'+host+':'+port+'/websocket';
   else 
     ws_str='ws://'+host+':'+port+'/websocket';


	try{

      wsconnect();

	} catch(exception) {
	   message(true,'Error: '+exception)
	}


    function chk_users(ignore,users) {
       retUsers='';
       cnt=0;
       userArr=users.split('|');

       for (var i=0; i<userArr.length; i++) {
          if (ignore.indexOf(userArr[i]) < 0) {
            if (cnt==0) {
              cnt++;
              retUsers=userArr[i];
            }
            else {
              if (userArr.length > 1) {
                if (userArr[i].indexOf('touch') < 0) {
                   retUsers=retUsers + '|' + userArr[i];
                 }
              }
              else
                retUsers=userArr[i];
            }
          }
       }

       if (retUsers.length == 0)
           return false;
 
      return true;
    }

    function hdiff(start, end) {
	  var jsnow = new Date();
	  var h=jsnow.getHours();

      if (end < start) {
        if ((h >= start && h <= 23) || (h >= 0 && h <= end)) {
          return true;
        }
      } else {
        if (h >= start && h <= end) {
          return true;
        }
      }

      return false;
    }

	function send(msg){
//		console.log('send called');
		if(msg == null || msg.length == 0){
			message(true,'No data....');
			return
		}
		try{
			socket.send(msg)
		} catch(exception){
			message(true,'Error: '+exception)
		}
	}


    function getnow() {
        var jsnow = new Date();
        var month=jsnow.getMonth()+1;
        var day=jsnow.getDate();
        var hour=jsnow.getHours();
        var mins=jsnow.getMinutes();
        var seconds=jsnow.getSeconds();

        (month<10)?month='0'+month:month;
        (day<10)?day='0'+day:day;
        (hour<10)?hour='0'+hour:hour;
        (mins<10)?mins='0'+mins:mins;
        (seconds<10)?seconds='0'+seconds:seconds;

        return month+'/'+day+'/'+jsnow.getFullYear()+'-'+hour+':'+mins+':'+seconds;
    }

	function message(sepcol,msg){        
        now = getnow();
		if (isNaN(msg)) {
            if(sepcol){
			    $('#msgsm').html(now+':'+msg+'<br>'+$('#msgsm').html());
                mcnt = $('#msgsm').html().length;
                kb = 1024;
                mb = 1048576;
                lines=$('#msgsm br').length;

         		if (msg.indexOf('done') > -1 || msg.indexOf('_') > -1 || msg.indexOf('reboot sent to') > -1 || msg.indexOf('dfstatus sent to') > -1 || msg.indexOf('pong') > -1 || msg.indexOf('OK') > -1 || msg.indexOf('Results') > -1 || msg.indexOf('Thawing') > -1 || msg.indexOf('Freezing') > -1 || msg.indexOf('copied') > -1) {
     		        $('#cntr').html(Number($('#cntr').html()) + 1);
		        }

                if (lines > ", ?LINES, ") {
//                     window.location.href='/esysman';
                    $('#msgsm').html('');
                    $('#cntsm').html('0K/0L');
                    send('0:clearsmsg:');
                }
                else {
                    mcnt = (mcnt > mb ? (mcnt / mb).toFixed(2) +'MB': mcnt > kb ? (mcnt / kb).toFixed(2) + 'KB' : mcnt + 'B') + '/' + lines +'L';
                    $('#cntsm').html(mcnt);
                }
            }
        
          else if (msg.indexOf('from')>0) {

			$('#msgsm').html(now+':'+msg+'<br>'+$('#msgsm').html());
                mcnt = $('#msgsm').html().length;
                kb = 1024;
                mb = 1048576;
                lines=$('#msgsm br').length;
                if (lines > ", ?LINES, ") {
                    $('#msgsm').html('');
                    $('#cntsm').html('0K/0L');
                }
                else {
                    mcnt = (mcnt > mb ? (mcnt / mb).toFixed(2) +'MB': mcnt > kb ? (mcnt / kb).toFixed(2) + 'KB' : mcnt + 'B') + '/' + lines +'L';
                    $('#cntsm').html(mcnt);
                }

            } 
            else {
			    $('#msgcl').html(now+':'+msg+'<br>'+$('#msgcl').html());
                mcnt = $('#msgcl').html().length;
                kb = 1024;
                mb = 1048576;
                lines=$('#msgcl br').length;
                if (lines > ", ?LINES, ") {
//                      window.location.href='/esysman';
                    $('#msgcl').html('');
                    $('#cntcl').html('0K/0L');
                    send('0:clearcmsg:');
                }
                else {
                    mcnt = (mcnt > mb ? (mcnt / mb).toFixed(2) +'MB': mcnt > kb ? (mcnt / kb).toFixed(2) + 'KB' : mcnt + 'B') + '/' + lines +'L';
                    $('#cntcl').html(mcnt);
                }
            }
        }
		else {
			$('#msgsm').html(now+':'+socket_status(msg)+'<br>'+$('#msgsm').html());
                mcnt = $('#msgsm').html().length;
                kb = 1024;
                mb = 1048576;
                lines=$('#msgsm br').length;
                if (lines > ", ?LINES, ") {
//                    window.location.href='/esysman';
                    $('#msgsm').html('');
                    $('#cntsm').html('0K/0L');
                }
                else {
                    mcnt = (mcnt > mb ? (mcnt / mb).toFixed(2) +'MB': mcnt > kb ? (mcnt / kb).toFixed(2) + 'KB' : mcnt + 'B') + '/' + lines +'L';
                    $('#cntsm').html(mcnt);
                }

        }
	}



	function socket_status(readyState){
		if (readyState == 0)
			return 'Socket status: ' + socket.readyState +' (Connecting)'
		else if (readyState == 1)
			return 'Socket status: ' + socket.readyState + ' (Open)'
		else if (readyState == 2)
			return 'Socket status: ' + socket.readyState + ' (Closing)'
		else if (readyState == 3)
			return 'Socket status: ' + socket.readyState +' (Closed)'
	}

	$('#wsconnect').click(function(){
        wsconnect();
	});

	$('#wsdisconnect').click(function(){
        send('close')
	});

    $('#smclear').click(function(){
        $('#msgsm').html('');
        $('#cntsm').html('0K/L');
        send('0:clearsmsg:');
    });

    $('#cmclear').click(function(){
        $('#msgcl').html('');
        $('#cntcl').html('0K/0L');
        send('0:clearcmsg:');
    });

    $('#duclear').click(function(){
        $('#msgdup').html('');
        $('#cntdup').html('0K/0L');
        send('0:cleardmsg:');
    });

    $('#cntrst').click(function(){
        $('#cntr').html('0');
    });

    var obj = '';

	$(document).on('click', '#dbut', function(){
        obj = $(this);

        $('#dialogtext2').html($(obj).parent().next('td').html());
        $('#dialog2').dialog({
        title:' Confirm Delete Script',
        buttons: [{
            text: 'Confirm delete script!',
            click: function() {

              if ($(obj).parent().next('td').html() == $('#lncmddiv').html()) {
                $('#lncmddiv').html('')
              }
              else if ($(obj).parent().next('td').html() == $('#lnexediv').html()) {
                $('#lnexediv').html('')
              }
              else if ($(obj).parent().next('td').html() == $('#lnmsidiv').html()) {
                $('#lnmsidiv').html('')
              }

              $(obj).closest('tr').remove();
              send('0:delscrfile:' + $(obj).parent().next('td').html());

              $( this ).dialog( 'close' );
            }
          }]
        });

	});

	$(document).on('click', '#lbut', function(){
        if ($(this).parent().next('td').html().indexOf('.cmd')>0) {
          $('#lncmddiv').html($(this).parent().next('td').html());
          send('0:lnscrfile:' + $(this).parent().next('td').html() + '+' + 'any.cmd');
        }
        else if ($(this).parent().next('td').html().indexOf('.exe')>0) {
          $('#lnexediv').html($(this).parent().next('td').html());
          send('0:lnscrfile:' + $(this).parent().next('td').html() + '+' + 'any.exe');
        }
        else if ($(this).parent().next('td').html().indexOf('.msi')>0) {
          $('#lnmsidiv').html($(this).parent().next('td').html());
          send('0:lnscrfile:' + $(this).parent().next('td').html() + '+' + 'any.msi');
        }

	});

	$(document).on('click', '#rbut', function(){     
      var fnameo = $(this).parent().next('td').html();
//      fname = fnameo.split('.');
      var ok = true;
      while (ok) {
        var fnamex=prompt('Rename file',fnameo);
        if (fnamex == null) {
          ok = false;
        } else if (fnamex.length > 0){
          var regex=/^[a-zA-Z0-9-_\.]+$/;
          if (!fnamex.match(regex)) {
            ok = true;
          } else {
            ok = false;
            $(this).parent().next('td').html(fnamex);
            send('0:renscrfile:' + fnameo + '+' + fnamex);
            showmngscrbox = false;
            $('#mngscripts').click();
          }
        }
    }
	});

   var notcmd = false;

	$(document).on('click', '#ebut', function(){     
          $('#scrslist').hide();
          $('#editscr').show();
          notcmd = false;

          $('#scrname').html($(this).parent().next('td').html());
          send('0:editscrfile:' + $(this).parent().next('td').html());
	});

	$(document).on('click', '#scredcancel', function(){     
          $('#editscr').hide();
          $('#scrslist').show();
	});

	$(document).on('click', '#scrsave', function(){
      if (($('#scripttext').val().length > 0 || notcmd) && $('#scrdesc').val().length > 0) { 
        send('0:savescrfile:' + $('#scrname').html() + '^' + $('#scripttext').val() + '^' + $('#scrdesc').val());
        $('#scripttext').val('');
        $('#editscr').hide();
        //$('#scrslist').show();
        showmngscrbox = false;
        $('#mngscripts').click();
      } else {
        alert('Script text and script description must not be blank!');
      }
	});

	$(document).on('click', '#fncbut', function(){     
      var $temp = $('<input>');
      $('body').append($temp);
      $temp.val($(this).parent().next('td').html()).select();
      document.execCommand('copy');
      $temp.remove();
      $('#fncp').finish().show().delay(2000).fadeOut('slow');
	});


    var addscrf = false;

	$(document).on('click', '#addscrf', function(){     
      $('#scripttext').val('');
      $('#scrdesc').val('')
      $('#scrslist').hide();
      $('#editscr').show();
      $('#scrname').html('0temp.cmd');
      $('#scripttext').focus();
	});

    $(document).on('click', '#closescrslist', function(){
      showmngscrbox = true;
      $('#mngscripts').click();
    });

    $(document).on('change', '#selfile', function(evt){
      max = $(this)[0].files[0].size

      fSize = max; 
      i=0;
      while(fSize>900){
        fSize/=1024;
        i++;
      }

      var fSExt = new Array('Bytes', 'KB', 'MB', 'GB');
      var bitsStr = Math.round(fSize*100)/100 + ' ' + fSExt[i];

      $('#upprog').html('0% Uploaded.... of ' + bitsStr);
    });

    $(document).on('submit', '#mypost', function(evt){
//	  evt.preventDefault();

	  var formData = new FormData($(this)[0]);

	  $.ajax({
	    url: '/upload',
	    type: 'POST',
	    data: formData,
//	    async: false,
	    cache: false,
	    contentType: false,
	    enctype: 'multipart/form-data',
	    processData: false,
//        success: function(d) {
//          console.log('success');
//        },
        xhr: function() {
          var myXhr = $.ajaxSettings.xhr();
          if(myXhr.upload){
            myXhr.upload.addEventListener('progress',progress, false);
          }
          return myXhr;
        }
	  });

	  return false;
	});

//http://stackoverflow.com/questions/23219033/show-a-progress-on-multiple-file-upload-jquery-ajax

function progress(e){

    if(e.lengthComputable){
      var max = e.total;
      var current = e.loaded;
      
// http://stackoverflow.com/questions/7497404/get-file-size-before-uploading

      var fSExt = new Array('Bytes', 'KB', 'MB', 'GB');
      fSize = max; 
      i=0;
      while(fSize>900){
        fSize/=1024;
        i++;
      }

      var bitsStr = Math.round(fSize*100)/100 + ' ' + fSExt[i];

      var perc = parseInt((current * 100)/max);
      $('#upprog').html(perc + '% Uploaded.... of ' + bitsStr);
//        console.log(Percentage);

      if(perc >= 100){
       // process completed  
        showmngscrbox = false;
        $('#mngscripts').click();
      }
    }  
 }

    $(document).on('click', '#lockscr', function(evt){
      lockscr();
    });

    $(document).keydown(function(objEvent) {
      if (objEvent.keyCode == 9) { //tab 
        objEvent.preventDefault(); 
      }
    });

    $(document).on('click', '#unlockscr', function(evt){
      $('#unlockscr').hide();
      $('#unlockscrpasswd').show();
      $('#unlockscrpasswd').focus();
    });

    $(document).on('keydown', '#unlockscrpasswd',function(e) {
      if(e.which == 13) {
        var ok = true;
        var passwd=$('#unlockscrpasswd').val();
        if (passwd.length == 0) {
          $('#unlockscr').show();
          $('#unlockscr').focus();
          $('#unlockscrpasswd').val('');
          $('#unlockscrpasswd').hide();
          e.preventDefault(); 
        } else 

          if (passwd.length > 0){
            var regex=/^[a-zA-Z0-9-_\.]+$/;
            if (passwd.match(regex)) {
              if (passwd == '", ?LOCKSCRPASSWD,"') {
                ok = false;

                $('#unlockscr').show();
                $('#unlockscr').focus();
                $('#unlockscrpasswd').val('');
                $('#unlockscrpasswd').hide();

                $('#lockpane').hide();
                send('0:lockloginok:');
              } else {
                ok = false;
                send('0:lockloginfailed:');
              }
            }
          }

      } else if (e.which == 27) {
        $('#unlockscr').show();
        $('#unlockscr').focus();
        $('#unlockscrpasswd').val('');
        $('#unlockscrpasswd').hide();
      }
    });


",
(jsAll(?ROOMS,<<"ping">>))/binary,
(jsAllConfirm(?ROOMS,<<"reboot">>))/binary,
(jsAllConfirm(?ROOMS,<<"shutdown">>))/binary,
(jsAllConfirm(?ROOMS,<<"dfthaw">>))/binary,
(jsAllConfirm(?ROOMS,<<"dffreeze">>))/binary,
(jsAll(?ROOMS,<<"wake">>))/binary,
(jsAll(?ROOMS,<<"dfstatus">>))/binary,
(jsAll(?ROOMS,<<"net_restart">>))/binary,
(jsAll(?ROOMS,<<"net_stop">>))/binary,
(jsAll(?ROOMS,<<"loggedon">>))/binary,
(jsAll(?ROOMS,<<"copy">>))/binary,
(jsAll(?ROOMS,<<"com">>))/binary,
(mkjsAllSelect_copy(?ROOMS))/binary,
(mkjsSelect_copy(?ROOMS))/binary,
(mkjsAllSelect_com(?ROOMS))/binary,
(mkjsSelect_com(?ROOMS))/binary,
(mkjsSelectAllChk(?ROOMS))/binary,
(mkjsUnSelectAllChk(?ROOMS))/binary,
(mkjsToggleAllChk(?ROOMS))/binary,
(mkcomButtons(?ROOMS))/binary,
(mkjsComAll(?ROOMS,<<"ping">>))/binary,
(mkjsComAll(?ROOMS,<<"reboot">>))/binary,
(mkjsComAll(?ROOMS,<<"shutdown">>))/binary,
(mkjsComAll(?ROOMS,<<"wake">>))/binary,
(mkjsComAll(?ROOMS,<<"dfthaw">>))/binary,
(mkjsComAll(?ROOMS,<<"dffreeze">>))/binary,
(mkjsComAll(?ROOMS,<<"dfstatus">>))/binary,
(mkjsComAll(?ROOMS,<<"net_restart">>))/binary,
(mkjsComAll(?ROOMS,<<"net_stop">>))/binary,
(mkjsComAll(?ROOMS,<<"loggedon">>))/binary,
(mkjsComAll(?ROOMS,<<"copy">>))/binary,
(mkjsComAll(?ROOMS,<<"com">>))/binary,
(chk_dupe_usersa(?ROOMS))/binary,
(chk_dupe_users(?ROOMS))/binary,
(refresh_cons(?ROOMS))/binary,
(toggles(?ROOMS))/binary,
(rms_keys(Get_rms,Get_rms))/binary,
"

    interval_chk_dupes=setInterval(chk_dupe_users,60000);

}//End else - has websockets
    var showmngscrbox = false

    $('#mngscripts').click(function(){
          if (!showmngscrbox) {
              $('#mngscrbox').css('z-index', 2000);
              $('#mngscrbox').show();
              $('#mngscrbox').css('position', 'absolute');
              $('#mngscrbox').css('z-index', parseInt($('.msgc').css('z-index')) + 2);
              showmngscrbox = true;
              send('localhost@domain:list_ups_dir:0');
          }
          else {
              $('#mngscrbox').hide();
              showmngscrbox = false;
          }
	});

       var msgcsm_hgt_old = 0;
       var msgc_hgt_old = 0;

	$('#smbig').click(function(){
          if ($('.msgcsm').height() < 1024) {
	      msgcsm_hgt_old = $('.msgcsm').height();
              $('.msgcsm').height(1024);
              $('.msgcsm').width(1024);
              $('.msgcsm').css('position', 'absolute');
              $('.msgcsm').css('z-index', parseInt($('.msgc').css('z-index')) + 1);
          }
          else {
              $('.msgcsm').height(msgcsm_hgt_old);
              $('.msgcsm').width(550);
              $('.msgc').css('position', 'relative');
          }
	});

	$('#clbig').click(function(){
          if ($('.msgc').height() < 1024) {
              msgc_hgt_old = $('.msgc').height();
              $('.msgc').height(1024);
              $('.msgc').width(1024);
              $('.msgc').css('position', 'absolute');
              $('.msgc').css('z-index', parseInt($('.msgcsm').css('z-index')) + 1);
          }
          else {
              $('.msgc').height(msgc_hgt_old);
              $('.msgc').width(550);
              $('.msgc').css('position', 'relative');
          }
	});

    $('#sacs').click(function(){
        if($(':checkbox:lt(1)').is(':checked')){
          $(':checkbox').removeAttr('checked');
        }
        else {
          $(':checkbox').attr('checked', 'checked');  
      }
    });

    $('#logout').click(function() {
      window.location='/esysman/logout';
    });

});

</script>
</head>

<body bgcolor='#333333' style='color:yellow;'>
<div id='lockpane'>
<!--
<input type='button' id='unlockscr' class='button' value='Unlock'>
-->
<button id='unlockscr' class='ui-button ui-widget ui-corner-all'>Unlock</button>
<input type='password'class='ui-widget' id='unlockscrpasswd'>
</div>

<div id='wrapper'>

<div id='menu' class='fl'>

<div id='rooms_title' class='fl ui-widget ui-corner-all'>
[0]-Rooms
</div>

<div id='switcher'>
",
(switcher(?ROOMS))/binary,
"
</div>

</div>

<div class='brk'></div>

<div id='commands'>

<div id='com_title' class='ui-widget'>
 Commands -- Auto Wks Shutdown Time: 
 <input style='width:25px;' id='shutdownTimeH'  type='text' name='shutdownTimeH' maxlength=2 value='",?SHUTDOWNSTART,"'/> <->
 <input style='width:25px;' id='shutdownTimeH2'  type='text' name='shutdownTimeH2' maxlength=2 value='",?SHUTDOWNEND,"'/>
 <select id='shutdownTimerSwitch' class='ui-widget' name='shutdownTimerSwitch'>
   <option ",?SELECTEDON," value='1'>On</option>
   <option ",?SELECTEDOFF," value='0'>Off</option>
 </select>
 ( <span id='cntr' class='ui-widget'>0</span> )

<button id='cntrst' class='ui-button ui-widget ui-corner-all'>Reset</button>

<button id='lockscr' class='ui-button ui-widget ui-corner-all'>Lock</button>
<button id='mngscripts' class='ui-button ui-widget ui-corner-all'>Manage Scripts</button>
<span id='fncp' style='display:none'>File name copied to Clipboard!</span>
<div id='mngscrbox' class='ui-widget-content'></div>

</div> 

 <div id='tcoms'>
<button id='wsconnect' class='ui-button ui-widget ui-corner-all' title='Connect to server...' />Connect</button>
<button id='wsdisconnect' class='ui-button ui-widget ui-corner-all' title='Disconnect from server...' />Disconnect</button>",
(case is_list(login_is()) of
	 true -> <<"<button id='logout' class='ui-button ui-widget ui-corner-all' title='Logout' />Logout</button><br>">>;
	 false -> <<"">>
 end)/binary,
"
<div class='brk'></div>
<button id='sacs' class='ui-button ui-widget ui-corner-all' title='Select/Unselect all commands' />Select/UnSelect All Coms</button>
<div class='brk'></div>
",
( mkAllRoomsComs([
				 {<<"ping">>,<<"Ping All">>},
				 {<<"reboot">>,<<"Reboot All">>},
				 {<<"shutdown">>,<<"Shutdown All">>},
				 {<<"wake">>,<<"Wake All">>},
				 {<<"dfthaw">>,<<"DeepFreeze Thaw All">>},
				 {<<"dffreeze">>,<<"DeepFreeze Freeze All">>},
				 {<<"dfstatus">>,<<"DeepFreeze Status All">>},
				 {<<"net_restart">>,<<"Restart Service All">>},
				 {<<"net_stop">>,<<"Stop Service All">>},
				 {<<"loggedon">>,<<"Logged On All">>}
				]))/binary,
"
 </div>

 <div id='tinputs'>
",
(mkAllRoomsComsInput({<<"copy">>,<<"Copy All">>}))/binary,
(mkAllRoomsComsInput({<<"com">>,<<"Com All">>}))/binary,
(mkAllRoomsSelectUnselectToggleAll(?ROOMS))/binary,
"
 </div>

 <div id='tmsgs' class='tmsgsc'>
   <div id='mtop' class='mtopc'> <button id='smbig' class='mbig ui-button ui-widget ui-corner-all' title='View more lines...'/>+</button> <button id='smclear' class='clr ui-button ui-widget ui-corner-all' title='Clear Server Logs'>C</button> Server Messages (most recent at top) <div id='cntsm'>0KB/0L</div></div>
	 <div id='msg-div'>
	 <div id='msgsm' class='msgcsm'></div>
   </div>
 </div>

 <div id='tmsgscl' class='tmsgsc'>
   <div id='mtopcl' class='mtopc'> <button id='clbig' class='mbig ui-button ui-widget ui-corner-all' title='View more lines...'/>+</button> <button id='cmclear' class='clr ui-button ui-widget ui-corner-all' title='Clear Server Logs'>C</button> Client Messages (most recent at top) <div id='cntcl'>0KB/0L</div></div>
	 <div id='msg-divcl'>
	   <div id='msgcl' class='msgc'></div>
     </div>
 </div>

 <div id='tmsgsdup' class='tmsgsc'>
   <div id='mtopdup' class='mtopcd'><button id='duclear' class='clr ui-button ui-widget ui-corner-all' title='Clear Server Logs'>C</button> Duplicate Users (most recent at top) <div id='cntdup'>0KB/0L</div></div>
	 <div id='msg-div-dup'>
	 <div id='msgdup' class='msgcd'></div>
   </div>
 </div>

 </div>

 <div class='brk'></div>

 <div id='workstations'>

",
(mkRooms(?ROOMS))/binary,
"
 </div>
 </div>

<div id='big_msg'></div>

</body>
</html">>, Req),
	{ok, Req2, Opts}. %% main page

 %%

 init_open([Room|_]) ->
	 [Rm|_]=Room,
<<"
					  $('#",Rm/binary,"').show();
					  $('#",Rm/binary,"_coms').show();
					  $('#",Rm/binary,"_comsInputcopy').show();
					  $('#",Rm/binary,"_comsInputcom').show();

					  $('#",Rm/binary,"_selunseltogall').show();

                      $('#",Rm/binary,"toggle').click();

">>.

%%

toggles([Room|Rooms]) ->
	<<(toggles_rm(Room))/binary,(toggles(Rooms))/binary>>;
toggles([]) ->
	<<>>.

%%

toggles_rm([Rm|_]) ->
	<<"
	 $('#",Rm/binary,"toggle').click(function(){
",
	  (toggle_items(?ROOMS,Rm))/binary,
"
	 });
">>.

%%

toggle_items([Room|Rooms],Rm) ->
	<<(toggle_item(Room,Rm))/binary,(toggle_items(Rooms,Rm))/binary>>;
toggle_items([],_) ->
	<<>>.

%%

toggle_item([Room|_],Rm) ->
	case Room of
		Rm ->
			<< "
		 $('#",Rm/binary,"').show();
		 $('#",Rm/binary,"_coms').show();
		 $('#",Rm/binary,"_comsInputcopy').show();
		 $('#",Rm/binary,"_comsInputcom').show();
 	     $('#",Rm/binary,"_selunseltogall').show();
		 $('#",Rm/binary,"toggle').removeClass('rm_selected');
		 $('#",Rm/binary,"toggle').removeClass('rm_not_selected');
		 $('#",Rm/binary,"toggle').addClass('rm_selected');
">>;
		_ -> 
			<<"
		 $('#",Room/binary,"').hide();
		 $('#",Room/binary,"_coms').hide();
		 $('#",Room/binary,"_comsInputcopy').hide();
		 $('#",Room/binary,"_comsInputcom').hide();
	     $('#",Room/binary,"_selunseltogall').hide();
		 $('#",Room/binary,"toggle').removeClass('rm_selected');
		 $('#",Room/binary,"toggle').removeClass('rm_not_selected');
		 $('#",Room/binary,"toggle').addClass('rm_not_selected')

">>
	end;
toggle_item([],_) ->
	<<>>.

%%

jsAll([Room|Rooms],Com) ->
	[Rm|_]=Room,
	<<(case Com of
		<<"com">>  -> ifcomcopy(Rm,Com);
		<<"copy">> -> ifcomcopy(Rm,Com);
		_ ->
			<<"

	 $('#",Com/binary,"All",Rm/binary,"').click(function(){
",Com/binary,"All",Rm/binary,"();
			 message(true,'",Com/binary," All ",Rm/binary,"...')
	 });">>
	end)/binary,(jsAll(Rooms,Com))/binary>>;
jsAll([],_) ->
	<<>>.

%%

ifcomcopy(Rm,Com) ->
<<"
	 $('#",Com/binary,"All",Rm/binary,"').click(function(){
		 if($('#",Com/binary,"AllInput",Rm/binary,"').val().length){
			 ",Com/binary,"All",Rm/binary,"();
			 message(true,'",Com/binary," All ",Rm/binary,"...')
		 } else {
			 $('#",Com/binary,"AllInput",Rm/binary,"').val('!');
			 message(true,'",Com/binary," All ",Rm/binary," is blank!')
		 }
	 });

">>.

%%

jsAllConfirm([Room|Rooms],Com) ->
	[Rm|_]=Room,
	<<"

	 $('#",Com/binary,"All",Rm/binary,"').click(function(){

        $('#dialogtext').html(' ",Com/binary," All ",Rm/binary," systems...');
        $('#dialog').dialog({
        title:' ",Com/binary," All ",Rm/binary," Systems...',
        buttons: [{
            text: ' ",Com/binary," All ",Rm/binary," systems?',
            click: function() {
              rall=true;     
              ",Com/binary,"All",Rm/binary,"();
              $( this ).dialog( 'close' );
            }
          }]
        })

	 });

",(jsAllConfirm(Rooms,Com))/binary>>;
jsAllConfirm([],_) ->
	<<>>.

%%

mkjsAllSelect_copy([Room|Rooms]) ->
	<<(mkjsAllSelectRm_copy(Room))/binary,(mkjsAllSelect_copy(Rooms))/binary>>;
mkjsAllSelect_copy([]) ->
	<<>>.

mkjsAllSelectRm_copy([Room|Rows]) ->
	<<"

 $('#copyAllSelect",Room/binary,"').change(function(){

	 $('#copyAllInput",Room/binary,"').val($('#copyAllSelect",Room/binary," option:selected').text());
	 ",(jsAllSelectRows_copy(Room,Rows))/binary,"
 });

 ">>.

%%

jsAllSelectRows_copy(Room,[Row|Rows]) ->
	<<(jsAllSelect_copy(Room,Row))/binary,(jsAllSelectRows_copy(Room,Rows))/binary>>;
jsAllSelectRows_copy(_Room,[]) ->
	<<>>.

%%

jsAllSelect_copy(Rm,[{Wk,_FQDN,_MacAddr,_Os}|Wks]) ->
	case Wk of
		<<".">> ->	jsAllSelect_copy(Rm,Wks);
		_ ->
			<<"
	 if(
		 ($('#copyAll",Rm/binary,"check').prop('checked') && $('#",Wk/binary,"check').prop('checked')) ||
		 (!$('#copyAll",Rm/binary,"check').prop('checked') && 
			 (!$('#",Wk/binary,"check').prop('checked') || $('#",Wk/binary,"check').prop('checked')))
	   )
		 $('#copyfn_",Wk/binary,"').val($('#copyAllInput",Rm/binary,"').val());
 ",(jsAllSelect_copy(Rm,Wks))/binary>>
	end;
jsAllSelect_copy(_Room,[]) ->
	<<>>.

%%

mkjsSelect_copy([Room|Rooms]) ->
	<<(mkjsSelectRm_copy(Room))/binary,(mkjsSelect_copy(Rooms))/binary>>;
mkjsSelect_copy([]) ->
	<<>>.

%%

mkjsSelectRm_copy([_Room|Rows]) ->
	jsSelectRows_copy(Rows).

jsSelectRows_copy([Row|Rows]) ->
	<<(jsSelect_copy(Row))/binary,(jsSelectRows_copy(Rows))/binary>>;
jsSelectRows_copy([]) ->
	<<>>.

%%

jsSelect_copy([{Wk,_FQDN,_MacAddr,_Os}|Wks]) ->
	case Wk of
		<<".">> ->	jsSelect_copy(Wks);
		_ ->
			<<"

 $('#copyselect",Wk/binary,"').change(function(){
	 $('#copyfn_",Wk/binary,"').val($('#copyselect",Wk/binary," option:selected').text());
 });

 ",(jsSelect_copy(Wks))/binary>>
	end;
jsSelect_copy([]) ->
	<<>>.

%%

mkjsAllSelect_com([Room|Rooms]) ->
	<<(mkjsAllSelectRm_com(Room))/binary,(mkjsAllSelect_com(Rooms))/binary>>;
mkjsAllSelect_com([]) ->
	<<>>.

%%

mkjsAllSelectRm_com([Room|Rows]) ->
	<<"

 $('#comAllSelect",Room/binary,"').change(function(){

	 $('#comAllInput",Room/binary,"').val($('#comAllSelect",Room/binary," option:selected').text());
	 ",(jsAllSelectRows_com(Room,Rows))/binary,"
 });

">>.

%%

jsAllSelectRows_com(Room,[Row|Rows]) ->
	<<(jsAllSelect_com(Room,Row))/binary,(jsAllSelectRows_com(Room,Rows))/binary>>;
jsAllSelectRows_com(_Room,[]) ->
	<<>>.

%%

jsAllSelect_com(Rm,[{Wk,_FQDN,_MacAddr,_Os}|Wks]) ->
	case Wk of
		<<".">> ->	jsAllSelect_com(Rm,Wks);
		_ ->
<<"
	 if(
		 ($('#comAll",Rm/binary,"check').prop('checked') && $('#",Wk/binary,"check').prop('checked')) ||
		 (!$('#comAll",Rm/binary,"check').prop('checked') && 
			 (!$('#",Wk/binary,"check').prop('checked') || $('#",Wk/binary,"check').prop('checked')))
	   )
		 $('#comstr_",Wk/binary,"').val($('#comAllInput",Rm/binary,"').val());
 ",(jsAllSelect_com(Rm,Wks))/binary>>
	end;
jsAllSelect_com(_Room,[]) ->
	<<>>.
 
%%

mkjsSelect_com([Room|Rooms]) ->
	<<(mkjsSelectRm_com(Room))/binary,(mkjsSelect_com(Rooms))/binary>>;
mkjsSelect_com([]) ->
	<<>>.

%%

mkjsSelectRm_com([_Room|Rows]) ->
	jsSelectRows_com(Rows).

jsSelectRows_com([Row|Rows]) ->
	<<(jsSelect_com(Row))/binary,(jsSelectRows_com(Rows))/binary>>;
jsSelectRows_com([]) ->
	<<>>.

%%

jsSelect_com([{Wk,_FQDN,_MacAddr,_Os}|Wks]) ->
	case Wk of
		<<".">> ->	jsSelect_com(Wks);
		_ ->
<<"

 $('#comselect",Wk/binary,"').change(function(){
	 $('#comstr_",Wk/binary,"').val($('#comselect",Wk/binary," option:selected').text());
 });

 ",(jsSelect_com(Wks))/binary>>
	end;
jsSelect_com([]) ->
	<<>>.

%%

mkjsSelectAllChk([Room|Rooms]) ->
	[Rm|_]=Room,
	<<"
 $('#selectAll",Rm/binary,"').click(function(){
     $('#",Rm/binary," input:checkbox').each(function() {
         $(this).prop('checked', true);
     });
 });

",(mkjsSelectAllChk(Rooms))/binary>>;
mkjsSelectAllChk([]) ->
	<<>>.

%%

mkjsUnSelectAllChk([Room|Rooms]) ->
	[Rm|_]=Room,
	<<"
 $('#unselectAll",Rm/binary,"').click(function(){
     $('#",Rm/binary," input:checkbox').each(function() {
         $(this).prop('checked', false);
     });
 });

",(mkjsUnSelectAllChk(Rooms))/binary>>;
mkjsUnSelectAllChk([]) ->
	<<>>.

%%

mkjsToggleAllChk([Room|Rooms]) ->
	[Rm|_]=Room,
	<<"
 $('#toggleAll",Rm/binary,"').click(function(){
     $('#",Rm/binary," input:checkbox').each(function() {
         this.checked = !this.checked;
     });
 });

",(mkjsToggleAllChk(Rooms))/binary>>;
mkjsToggleAllChk([]) ->
	<<>>.

%%

mkAllRoomsComs(Coms) ->
	mkARComs(?ROOMS,Coms).

%%

mkARComs([Room|Rooms],Coms) ->
	[Rm|_]=Room,
	<<"<div id='",Rm/binary,"_coms' class='room'>",(mkARComsComs(Rm,Coms))/binary,"</div>",(mkARComs(Rooms,Coms))/binary>>;
mkARComs([],_Coms) ->
	<<>>.

%%

mkARComsComs(Rm,[{Com,ComText}|Coms]) ->
	<<"

 <div class='fl'>
 <input id='",Com/binary,"All",Rm/binary,"check' type='checkbox' class='checkbox ui-widget' /></a>
  <button id='",Com/binary,"All",Rm/binary,"' class='ui-button ui-widget ui-corner-all' title='Send to all Workstations...'/>",ComText/binary,"</button>
 </div>

<div class='brk'></div>

",(mkARComsComs(Rm,Coms))/binary>>;
mkARComsComs(_Rm,[]) ->
	<<>>.

%%

 mkAllRoomsComsInput(Com) ->
	 mkARComsInput(?ROOMS,Com).

 mkARComsInput([Room|Rooms],ComT) ->
	 {Com,ComText}=ComT,
	 [Rm|_]=Room,
<<"

 <div id='",Rm/binary,"_comsInput",Com/binary,"' class='room'>
	 ",(mkARComsComsInput(Rm,ComT))/binary,"
 </div>

",(mkARComsInput(Rooms,{Com,ComText}))/binary>>;
mkARComsInput([],_Com) ->
	<<>>.

%%

mkARComsComsInput(Rm,{Com,ComText}) ->
	<<"

 <div class='fl'>

<div class='brk'></div>

 <input id='",Com/binary,"All",Rm/binary,"check' type='checkbox' class='checkbox ui-widget' /></a>
  <button id='",Com/binary,"All",Rm/binary,"' class='ui-button ui-widget ui-corner-all' title='Send to all Workstations...' />",ComText/binary,"</button>

 <div class='brk'></div>

 <select id='",Com/binary,"AllSelect",Rm/binary,"' class='fl ui-widget'>
	 ",

	  (case Com of
		   <<"copy">> ->
			   selections(?APPS);
		   <<"com">> ->
			   selections(?COMS)
	   end)/binary,
"
 </select>

<div class='brk'></div>

  <input id='",Com/binary,"AllInput",Rm/binary,"' type='text', name='",Com/binary,"AllInput' class='fl ui-widget'/>

 </div>
 ">>.

%%

mkAllRoomsSelectUnselectToggleAll([Room|Rooms]) ->
	 [Rm|_]=Room,
	 <<"
 <div class='brk'></div>

 <div id='",Rm/binary,"_selunseltogall' class='room'>

<div class='brk'></div>

	 ",(mkselunseltogAll(Rm))/binary,"
 </div>

 ",(mkAllRoomsSelectUnselectToggleAll(Rooms))/binary>>;
 mkAllRoomsSelectUnselectToggleAll([]) ->
	<<>>.

%%

mkselunseltogAll(Rm) ->
	<<"
  <button id='selectAll",Rm/binary,"' class='ui-button ui-widget ui-corner-all' title='Select all Workstations...' />Select All</button>

<div class='brk'></div>

  <button id='unselectAll",Rm/binary,"' class='ui-button ui-widget ui-corner-all' title='Unselect all Workstations...' />UnSelect All</button>

<div class='brk'></div>

  <button id='toggleAll",Rm/binary,"' class='ui-button ui-widget ui-corner-all' title='Toggle select/unselect all Workstations...' />Toggle All</button><br>
">>.

%%

mkRooms([Room|Rooms]) ->
	<<(mkRoom(Room))/binary,(mkRooms(Rooms))/binary>>;
mkRooms([]) ->
	<<>>.

%%

mkRoom([Room|Rows]) ->
	<<"

 <div id='",Room/binary,"' class='room'>
 ",(mkRoomRows(Rows,Room,1))/binary,"

 </div>

 ">>.

%%

mkRoomRows([Row|Rows],Rm,RowCnt) ->
	<<"
 <div id='",Rm/binary,"_row_",(list_to_binary(integer_to_list(RowCnt)))/binary,"'>",
	  (divhc(Rm,Row,1))/binary,
"
 </div>
 <div class='brk'></div>
 <div id='",Rm/binary,"_row_",(list_to_binary(integer_to_list(RowCnt)))/binary,"_Coms' style='display:none;'>",
	  << <<(divc(Wks))/binary>> || Wks <- Row >>/binary,
"
 </div>
 <div class='brk'></div>"
	 ,(mkRoomRows(Rows,Rm,RowCnt+1))/binary>>;
 mkRoomRows([],_Rm,_RowCnt) ->
	 <<>>.

%%

divhc(Rm,[{Wk,FQDN,MacAddr,_Os}|Wks],ColCnt) ->
	<<(case Wk of
		 <<".">> ->	<<"<div class='hltd'>.</div>">>;
			_ ->
			   <<"

<div id='",Wk/binary,"_hltd' class='hltd ",Rm/binary,"_col_",(list_to_binary(integer_to_list(ColCnt)))/binary,"'>

<div id='",Wk/binary,"status' class='status'>.</div>

<div class='wkchk'>
<input id='",Wk/binary,"check' type='checkbox' class='checkbox' /></div>

<button id='",Wk/binary, "Expr' class='ui-button ui-widget ui-corner-all' title='Expand Row' />E</button>

<div class='wk'>",FQDN/binary,"</div>



<div class='brk'></div>

<div id='",Wk/binary,"macaddr' class='macaddr'>",MacAddr/binary,"</div> <div id='",Wk/binary,"dfstatus' class='dfstatus'>DF?</div>

</div>

">>
	  end)/binary,(divhc(Rm,Wks,ColCnt+1))/binary>>;
divhc(_Rm,[],_ColCnt) ->
	<<>>.

%%

divc({Wk,_FQDN,_MacAddr,_Os}) ->
	case Wk of
		<<".">> ->	<<"<div class='ltd'>.</div>">>;
		   _ ->
<<"
<div id='",Wk/binary,"_ltd' class=\"ltd\">
<div id='",Wk/binary,"_ccell'>

<div class=\"lc\">

 <button id='ping_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='Ping' />P</button>
 <button id='reboot_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='Reboot' />R</button>
 <button id='shutdown_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='Shutdown' />S</button>
 <button id='loggedon_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='Logged On' />L</button>
 <button id='",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='Select Columns' />C</button>

<div class='brk'></div>

 <button id='dffreeze_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='DeepFreeze Freeze' />DFF</button>
 <button id='dfthaw_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='DeepFreeze Thaw' />DFT</button>
 <button id='dfstatus_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='DeepFreeze Statis' />DFS</button>

<div class='brk'></div>

 <button id='wake_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='Wake-On-LAN' />WOL</button>
 <button id='net_restart_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='Restart Service' />ReS</button>
 <button id='net_stop_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='Stop Service' />StS</button>

</div>

<div class='brk'></div>

<div>

<div class='brk'></div>
<div class='brk'></div>
 <button id='copy_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='Stop Service' />Copy</button>
<div class='brk'></div>
<select id='copyselect",Wk/binary,"' class='ui-widget'>
",
       (selections(?APPS))/binary,
"
</select>
 <input id='copyfn_",Wk/binary,"' type='text' class='ui-widget' /><br>



</div>

<div class='brk'></div>

<div>


 <button id='com_",Wk/binary,"' class='ui-button ui-widget ui-corner-all' title='Stop Service' />Com</button>
<div class='brk'></div>
<select id='comselect",Wk/binary,"' class='ui-widget'>
",
        (selections(?COMS))/binary,
"
</select>
<input id='comstr_",Wk/binary,"' type='text' class='ui-widget' />

</div>
</div>
</div>

<div id='dialog' style='display:none;' title=''>
Click button to <span id=dialogtext style='font-weight:bold;'>temp</span>...
</div>

<div id='dialog2' style='display:none;' title=''>
Click button to delete: <br><span id=dialogtext2 style='font-weight:bold;align:center;'>temp</span>...
</div>

">>
	end.

%%

selections([Com|Coms]) ->
<<"
<option value='",Com/binary,"'>",Com/binary,"</option>
",(selections(Coms))/binary>>;
selections([]) ->
<<>>.
	
%%

mkcomButtons([Room|Rooms]) ->
	<<(comButtonsRm(Room))/binary,(mkcomButtons(Rooms))/binary>>;
mkcomButtons([]) ->
	<<>>.

%%

comButtonsRm([Room|Rows]) ->
    comButtonsRows(Rows,Room,1).

comButtonsRows([Row|Rows],Rm,RowCnt) ->
	<<(comButtons(Row,Rm,RowCnt,1))/binary,(comButtonsRows(Rows,Rm,RowCnt+1))/binary>>;
comButtonsRows([],_Rm,_RowCnt) ->
	<<>>.

%%

comButtons([{Wk,FQDN,MacAddr,_Os}|Wks],Rm,RowCnt,ColCnt) ->
	case Wk of
		<<".">> -> << (comButtons(Wks,Rm,RowCnt,ColCnt+1))/binary >>;
		_ ->
	<<"

    $('#",Wk/binary,"_col').click(function(){
        $('.",Rm/binary,"_col_",(list_to_binary(integer_to_list(ColCnt)))/binary," input:checkbox').each(function() {
           this.checked = !this.checked;
       });
	});

    $('#",Wk/binary,"status').click(function(){
        $('#",Rm/binary,"_row_",(list_to_binary(integer_to_list(RowCnt)))/binary," input:checkbox').each(function() {
           this.checked = !this.checked;
       });
	});

    $('#",Wk/binary,"Expr').click(function(){
        $('#",Rm/binary,"_row_",(list_to_binary(integer_to_list(RowCnt)))/binary,"_Coms').slideToggle('slow');
	});

	$('#reboot_",Wk/binary,"').click(function(){
      if (rall==false) {
        $('#dialogtext').html('reboot');
        $('#dialog').dialog({
        title:'Reboot',
        buttons: [{
            text: 'Reboot ",Wk/binary,"?',
            click: function() {
              send('",FQDN/binary,":reboot:0');
              message(true,'Rebooting ",Wk/binary,"...');        
              $( this ).dialog( 'close' );
            }
          }]
        })
      } else {
        send('",FQDN/binary,":reboot:0');
        message(true,'Rebooting ",Wk/binary,"...');        
      }
	});


	$('#shutdown_",Wk/binary,"').click(function(){
      if (rall==false) {
        $('#dialogtext').html('shutdown');
        $('#dialog').dialog({
        title:'Shutdown',
        buttons: [{
            text: 'Shutdown ",Wk/binary,"?',
            click: function() {
              send('",FQDN/binary,":shutdown:0');
              message(true,'Shutting down ",Wk/binary,"...');        
              $( this ).dialog( 'close' );
            }
          }]
        })
      } else {
        send('",FQDN/binary,":shutdown:0');
        message(true,'Shutting down ",Wk/binary,"...');        
      }
	});

	$('#wake_",Wk/binary,"').click(function(){
		send('",FQDN/binary,":wol:",MacAddr/binary,"');
		message(true,'Waking ",Wk/binary,"...')
	});

	$('#ping_",Wk/binary,"').click(function(){
		send('",FQDN/binary,":ping:0');
		message(true,'Pinging ",Wk/binary,"...');
	});

	$('#net_restart_",Wk/binary,"').click(function(){
		send('",FQDN/binary,":net_restart:0');
		message(true,'Restarting service on ",Wk/binary,"...')
	});

	$('#net_stop_",Wk/binary,"').click(function(){
		send('",FQDN/binary,":net_stop:0');
		message(true,'Stopping service on ",Wk/binary,"...')
	});

	$('#dffreeze_",Wk/binary,"').click(function(){
      if (rall==false) {
        $('#dialogtext').html('DeepFreeze freeze');
        $('#dialog').dialog({
        title:'DeepFreeze Freeze',
        buttons: [{
            text: 'DeepFreeze Thaw ",Wk/binary,"?',
            click: function() {
              send('",FQDN/binary,":dffreeze:0');
              message(true,'DeepFreeze freezing ",Wk/binary,"...');        
              $( this ).dialog( 'close' );
            }
          }]
        })
      } else {
        send('",FQDN/binary,":dffreeze:0');
        message(true,'DeepFreeze freezing ",Wk/binary,"...');        
      }
	});

	$('#dfthaw_",Wk/binary,"').click(function(){
      if (rall==false) {
        $('#dialogtext').html('DeepFreeze thaw');
        $('#dialog').dialog({
        title:'DeepFreeze Thaw',
        buttons: [{
            text: 'DeepFreeze Thaw ",Wk/binary,"?',
            click: function() {
              send('",FQDN/binary,":dfthaw:0');
              message(true,'DeepFreeze Thawing ",Wk/binary,"...');        
              $( this ).dialog( 'close' );
            }
          }]
        })
      } else {
        send('",FQDN/binary,":dfthaw:0');
        message(true,'DeepFreeze Thawing ",Wk/binary,"...');        
      }
	});

	$('#dfstatus_",Wk/binary,"').click(function(){
		send('",FQDN/binary,":dfstatus:0');
		message(true,'DF Status sent ",Wk/binary,"...')
	});

	$('#loggedon_",Wk/binary,"').click(function(){
		send('",FQDN/binary,":loggedon:0');
		message(true,'loggedon sent ",Wk/binary,"...')
	});

	$('#copy_",Wk/binary,"').click(function(){
        if($('#copyfn_",Wk/binary,"').val().length){
		    send('",FQDN/binary,":copy:' + $('#copyfn_",Wk/binary,"').val());
		    message(true,'Copy sent ",Wk/binary,"...')
        } else {
            $('#copyfn_",Wk/binary,"').val('!');
		    message(true,'Copy file name blank! ",Wk/binary,"...')
        }
	});

	$('#com_",Wk/binary,"').click(function(){
        if($('#comstr_",Wk/binary,"').val().length){
		    send('",FQDN/binary,":com:' + $('#comstr_",Wk/binary,"').val());
		    message(true,'Command sent ",Wk/binary,"...')
        } else {
            $('#comstr_",Wk/binary,"').val('!');
		    message(true,'Command is blank! ",Wk/binary,"...')
        }
	});

",(comButtons(Wks,Rm,RowCnt,ColCnt+1))/binary>>
	end;

comButtons([],_Rm,_RowCnt,_ColCnt) ->
	<<>>.

%%

mkjsComAll([Room|Rooms],Com) ->
   <<(mkjsComAllRm(Room,Com))/binary,(mkjsComAll(Rooms,Com))/binary>>;
mkjsComAll([],_Com) ->
	<<>>.

%%

mkjsComAllRm([Rm|Rows],Com) ->
<<"

function ",Com/binary,"All",Rm/binary,"(){
",(mkjsComAllRows(Rows,Rm,Com))/binary,"
    rall=false;
}

">>.

%%

mkjsComAllRows([Row|Rows],Rm,Com) ->
	<<(mkjsComAllRow(Row,Rm,Com))/binary,(mkjsComAllRows(Rows,Rm,Com))/binary>>;
mkjsComAllRows([],_Rm,_Com) ->
    <<>>.

%%

mkjsComAllRow([{Wk,_FQDN,_MacAddr,_Os}|Wks],Rm,Com) ->
	case Wk of
		<<".">> ->
			mkjsComAllRow(Wks,Rm,Com);
		_ ->
			<<(case Com of
				   <<"copy">> ->
<<"
    if(
        ($('#",Com/binary,"All",Rm/binary,"check').prop('checked') && $('#",Wk/binary,"check').prop('checked')) ||
        (!$('#",Com/binary,"All",Rm/binary,"check').prop('checked') && 
            (!$('#",Wk/binary,"check').prop('checked') || $('#",Wk/binary,"check').prop('checked')))
      ){
	    $('#copyfn_",Wk/binary,"').val($('#copyAllInput",Rm/binary,"').val());
        $('#copy_",Wk/binary,"').click();
    }
">>;
				   _  ->
<<"
    if(
        ($('#",Com/binary,"All",Rm/binary,"check').prop('checked') && $('#",Wk/binary,"check').prop('checked')) ||
        (!$('#",Com/binary,"All",Rm/binary,"check').prop('checked') && 
            (!$('#",Wk/binary,"check').prop('checked') || $('#",Wk/binary,"check').prop('checked')))
      )
        $('#",Com/binary,"_",Wk/binary,"').click();
">>
			   end)/binary,(mkjsComAllRow(Wks,Rm,Com))/binary>>
	end;
mkjsComAllRow([],_Rm,_Com) ->
	<<>>.

%%

init2([Room|Rooms],Ref_cons_time) ->	
	<<(init2_rm(Room,Ref_cons_time))/binary,(init2(Rooms,Ref_cons_time))/binary>>;
init2([],_) ->
    <<>>.

%%

init2_rm([Rm|_],Ref_cons_time) ->
<<"
                     interval_",Rm/binary,"_ref_cons=setInterval(refresh_cons_",Rm/binary,",",(list_to_binary(integer_to_list(Ref_cons_time)))/binary,");

">>.

%%

get_rms_keys([Room|Rooms],Key) ->
	[Rm|_]=Room,
	[{Rm,Key}|get_rms_keys(Rooms,Key+1)];
get_rms_keys([],_) ->
	[].

%%

rms_keys([{Rm,_}|Rms],Rms_ks) ->
	<<"
    $('#",Rm/binary,"toggle').keydown(function(event) {
",
(loop_rms_keys(Rms_ks))/binary,
"
    });

",(rms_keys(Rms,Rms_ks))/binary>>;
rms_keys([],_) ->
	<<>>.

%%

loop_rms_keys([Rm|Rms]) ->
	<<(loop_rm_keys(Rm))/binary,(loop_rms_keys(Rms))/binary>>;
loop_rms_keys([]) ->
	<<>>.

%%

loop_rm_keys({Rm,Key}) ->
<<"
        if (event.which == ",(list_to_binary(integer_to_list(Key)))/binary,"){
            event.preventDefault();
            $('#",Rm/binary,"toggle').click();
        }
">>.

%%

chk_dupe_usersa(Rooms) ->
<<"
function  chk_dupe_users(){
        tot_cnt=0;
",
(chk_dupe_users_rms(Rooms))/binary,
"
}
">>.

chk_dupe_users_rms([Room|Rooms]) ->
	<<(jschkduRma(Room))/binary,(chk_dupe_users_rms(Rooms))/binary>>;
chk_dupe_users_rms([]) ->
	<<>>.

%%

jschkduRma([Rm|_Rows]) ->
	<<"
    chk_dupe_users_",Rm/binary,"();

">>.

%%

chk_dupe_users([Room|Rooms]) ->
	<<(jschkduRm(Room))/binary,(chk_dupe_users(Rooms))/binary>>;
chk_dupe_users([]) ->
	<<>>.

%%

jschkduRm([Rm|Rows]) ->
	<<"

function chk_dupe_users_",Rm/binary,"(){
    var dupe_",Rm/binary,"=[];

    var hash_",Rm/binary," = [];

	var ",Rm/binary,"cnt=0;
    

",
(jschkduRows(Rows,Rm))/binary,
"
    now = getnow();
    for (var key in hash_",Rm/binary,"){
        if (hash_",Rm/binary,".hasOwnProperty(key) && hash_",Rm/binary,"[key].length > 1) {
            $('#msgdup').html(now+':'+key+':['+hash_",Rm/binary,"[key]+']<br>'+$('#msgdup').html());
                mcnt = $('#msgdup').html().length;
                kb = 1024;
                mb = 1048576;
                lines=$('#msgdup br').length;
                if (lines > ", ?LINES, ") {
                    $('#msgdup').html('');
                    $('#cntdup').html('0K/0L');
                    send('0:cleardmsg:');
                }
                else {
                    mcnt = (mcnt > mb ? (mcnt / mb).toFixed(2) +'MB': mcnt > kb ? (mcnt / kb).toFixed(2) + 'KB' : mcnt + 'B') + '/' + lines +'L';
                    $('#cntdup').html(mcnt);
                }

        }
    }

    $('#",Rm/binary,"toggle').html('['+((",Rm/binary,"cnt>0)?",Rm/binary,"cnt:0).toString()+']-",Rm/binary,"');

}

">>.

%%

jschkduRows([Row|Rows],Rm) ->
	<<(jschkduRow(Row,Rm))/binary,(jschkduRows(Rows,Rm))/binary>>;
jschkduRows([],_Rm) ->
    <<>>.

%%

jschkduRow([{Wk,_FQDN,_MacAddr,_Os}|Wks],Rm) ->
	case Wk of
		<<".">> ->	jschkduRow(Wks,Rm);
		   _ ->
<<"

    var ignore_box = '",?IGNORESHUTDOWN,"';
    var ignore_box2 = '",?IGNOREDUPES,"';

    if ($('#",Wk/binary,"status').html()!='.' && ignore_box.indexOf('",Wk/binary,"') < 0 && ignore_box2.indexOf('",Wk/binary,"') < 0){
        dupe_",Rm/binary,".push($('#",Wk/binary,"status').html().toLowerCase());
        if (typeof hash_",Rm/binary,"[dupe_",Rm/binary,"[dupe_",Rm/binary,".length-1]] === 'undefined')
            hash_",Rm/binary,"[dupe_",Rm/binary,"[dupe_",Rm/binary,".length-1]] = [];
    
        hash_",Rm/binary,"[dupe_",Rm/binary,"[dupe_",Rm/binary,".length-1]].push('",Wk/binary,"');
        ",Rm/binary,"cnt++;
        tot_cnt++;
        $('#rooms_title').html('['+tot_cnt.toString()+']-'+'Rooms:');
    }
",(jschkduRow(Wks,Rm))/binary>>
	end;
jschkduRow([],_Rm) ->
	<<>>.

%%

switcher([Room|Rooms]) ->
	<<(switcher_rm(Room))/binary,(switcher(Rooms))/binary>>;
switcher([]) ->
	<<>>.

%%

switcher_rm([Rm|_Rows]) ->
	<<"
<button id='",Rm/binary,"toggle' class='ui-button ui-widget ui-corner-all' />[0]-",Rm/binary,"</button>
">>.

%%

refresh_cons([Room|Rooms]) ->
	<<(jsrefcons_rm(Room))/binary,(refresh_cons(Rooms))/binary>>;
refresh_cons([]) ->
	<<>>.

%%

jsrefcons_rm([Rm|Rows]) ->
	<<"

function refresh_cons_",Rm/binary,"(){
",
(jsrefcons_rows(Rows,Rm))/binary,
"
}
">>.

%%

jsrefcons_rows([Row|Rows],Rm) ->
	<<(jsrefcons_row(Row,Rm))/binary,(jsrefcons_rows(Rows,Rm))/binary>>;
jsrefcons_rows([],_Rm) ->
    <<>>.

%%

jsrefcons_row([{Wk,_FQDN,_MacAddr,_Os}|Wks],Rm) ->
	case Wk of
		<<".">> ->	jsrefcons_row(Wks,Rm);
		   _ ->
<<"

		$('#",Wk/binary,"_hltd').css('background-color','#000');
		$('#",Wk/binary,"_ltd').css('background-color','#000');
		$('#",Wk/binary,"dfstatus').css('color','cyan');
		$('#",Wk/binary,"dfstatus').css('background-color','#006666');
		$('#",Wk/binary,"status').css('color','red');
		$('#",Wk/binary,"status').css('background-color','#550000');
        $('#",Wk/binary,"status').html('.');

",(jsrefcons_row(Wks,Rm))/binary>>
	end;
jsrefcons_row([],_Rm) ->
	<<>>.

%

now_bin() ->
	{N1,N2,N3}=erlang:timestamp(), %now()
	list_to_binary(integer_to_list(N1)++integer_to_list(N2)++integer_to_list(N3)).