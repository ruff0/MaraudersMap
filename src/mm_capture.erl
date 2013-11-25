-module(mm_capture).
-author("Kevin Xu").
-export([start/1, stop/0, init/3]).
% ExpPrg holds the args for calling tshark - capture filter is excluding beacons, display filter is excluding no mac addresses.
% wlan[0] != 0x80 is to filter out beacon (Access Point) frames, -Y display filter is to only return rows with all 3 fields
% wlan.sa: Source Mac Address wlan.seq: Sequence Number radiotap.dbm_antsignal: signal strength

%% Reads settings from ?MODULE.settings in erlang terms
%% Starts a ?MODULE with default settings BUT with custom node location (nodeA, nodeB, nodeC)
start(ThisNode) ->
	{ok, Terms} = file:consult("mm_capture.settings"),
	[{tshark, ExtPrg}, {mm_receiver, Receiver}, {interface, Interface}, {blacklist, BlackList}, {whitelist, WhiteList}, _] = Terms,
	% Sets up interface, blacklist, whitelist, then redirects stderr to null (prevents annoying counter text)
	String = [ExtPrg, <<" -i ">>, Interface, <<" -f \"wlan[0] != 0x80 ">>, create_blacklist_filter(BlackList), create_whitelist_filter(WhiteList), <<"\" 2> /dev/null">> ],
	% String is probably not flattened, but open_port wants a flat string, not iolist
	Flattened = lists:flatten(io_lib:format("~s", [String])),
	io:format("~s~n", [Flattened]),
	spawn(?MODULE, init, [Flattened, Receiver, ThisNode]).

%% Stop the ?MODULE
stop() ->
	?MODULE ! stop.
	
%% Initialize the ?MODULE
init(ExtPrg, Receiver, ThisNode) ->
	register(?MODULE, self()),
	process_flag(trap_exit, true),
	Port = open_port({spawn, ExtPrg}, [in, exit_status, stream, {line, 255}]),
	loop(Port, Receiver, ThisNode).
	
%% Main ?MODULE loop
loop(Port, Receiver, ThisNode) ->
	receive
		{Port, Data} ->
			{_,{_,Chunk}} = Data, % strip out unnecessary data
			[MAC, SeqNo, SignalStrength] = string:tokens(Chunk, " "),
			% Sends a tuple to Receiver with , MAC address (only the first 17 characters, prevent multiple MACs), SS, SeqNo, and microsecond timestamp
			rpc:cast(Receiver, mm_receiver, store, [{ThisNode, {list_to_bitstring(string:left(MAC, 17)), list_to_integer(SignalStrength), list_to_integer(SeqNo), mm_misc:timestamp(microsecs)}}]),
			loop(Port, Receiver, ThisNode);
		stop ->
			erlang:port_close(Port),
			unregister(?MODULE),
			ok
	end.

create_blacklist_filter(BlackList) ->
	[[<<"and not wlan src host ">>, N, <<" ">>] || N <- BlackList].
	
create_whitelist_filter(WhiteList) ->
	[[<<"and wlan src host ">>, N, <<" ">>] || N <- WhiteList].