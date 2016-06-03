%%%--------------------------------------------------------------------
%%% CLIENT_DB MODULE
%%%
%%% @author: Mario Moro Hernandez upon a design by Natalia Chechina
%%% @copyright (C) 2014, RELEASE project
%%% @doc
%%%	Client_DB module for the Distributed Erlang instant messenger
%%%     (IM) application developed as a real benchmark for the Scalable 
%%%	Distributed Erlang extension of the Erlang/OTP language.
%%%
%%%	This module implementes the functionality for the database that
%%%	stores the cients that are loggen in at a given time in a system
%%%     similar to the system described in the Section 2 of the document
%%%     "Instant Messenger Architectures Design Proposal".
%%% @end 
%%% Created: 1 Jul 2014 by Mario Moro Hernandez
%%%--------------------------------------------------------------------
-module(client_db).

-export([start/1, stop/1, start_local/1, stop_local/1, client_db/1]).

%%%====================================================================
%%% API
%%%====================================================================

%%---------------------------------------------------------------------
%% @doc
%% Starts the clients database.
%%
%% @spec start(DB_Name)
%% @end
%%---------------------------------------------------------------------
start(DB_Name) ->
    global:register_name(DB_Name, spawn_link(fun() -> client_db(DB_Name) end)).

%%--------------------------------------------------------------------
%% @doc
%% Stops the client database.
%%
%% @spec stop(DB_Name)
%% @end
%%--------------------------------------------------------------------
stop(DB_Name) ->
    destroy(DB_Name),
    global:unregister_name(DB_Name).

%%---------------------------------------------------------------------
%% Starts the clients database, and registers it locally.
%%
%% @spec start_local(DB_Name)
%% @end
%%---------------------------------------------------------------------
start_local(DB_Name) ->
    Pid = spawn_link(fun() -> client_db(DB_Name) end),
    register(DB_Name, Pid).

%%--------------------------------------------------------------------
%% @doc
%% Stops a client database that has been started locally.
%%
%% @spec stop_local(DB_Name)
%% @end
%%--------------------------------------------------------------------
stop_local(DB_Name) ->
    destroy(DB_Name),
    unregister(DB_Name).

%%--------------------------------------------------------------------
%% @doc
%% client_db is first stage of the database process. It creates an ets
%% table after the atom specified as the parameter DB_Name.
%%
%% @spec client_db(DB_Name)
%% @end
%%--------------------------------------------------------------------
client_db(DB_Name) ->
    case ets:info(DB_Name) of
	undefined ->
	    create(DB_Name),
	    client_db_loop(DB_Name);
	_ ->
	    client_db_loop(DB_Name)
    end.

%%--------------------------------------------------------------------
%% @doc
%% client_db_loop constitutes the database process, and offers an inter-
%% face to interact with the ets table, allowing the input or retrieval
%% of information concerning the clients logged in the system. 
%%
%% @spec client_db_loop(DB_Name)
%% @end
%%--------------------------------------------------------------------
client_db_loop(DB_Name) ->
    receive
	{From, add, {Client_Name, Client_Pid, Client_Monitor_Pid}} -> 
	    add_client(DB_Name, Client_Name, Client_Pid, Client_Monitor_Pid),
	    send_reply(From, {client_added, ok}),
	    client_db_loop(DB_Name);
	{From, remove, {Client_Name}} ->
	    remove_client(DB_Name, Client_Name),
	    send_reply(From, {client_removed, ok}),
	    client_db_loop(DB_Name);
	{From, full_db} ->
	    A = retrieve_db(DB_Name),
	    send_reply(From, A),
	    client_db_loop(DB_Name);
	{From, update_pid, {Client_Name, Client_Pid}} ->
	    Answer = update_client_pid(DB_Name, Client_Name, Client_Pid),
	    send_reply(From, Answer),
	    client_db_loop(DB_Name);
	{From, update_monitor_pid, {Client_Name, Client_Monitor_Pid}} ->
	    Answer = update_client_monitor_pid(DB_Name, Client_Name, Client_Monitor_Pid),
	    send_reply(From, Answer),
	    client_db_loop(DB_Name);
	{From, peak, {Client_Name}} ->
	    C = peak_client(DB_Name, Client_Name),
	    send_reply(From, C),
	    client_db_loop(DB_Name);
	{From, peak_by_client_monitor, {Client_Monitor_Pid}} ->
	    C = peak_client_monitor(DB_Name, Client_Monitor_Pid),
	    send_reply(From, C),
	    client_db_loop(DB_Name);
	{From, retrieve, {Client_Name}} ->
	    C = retrieve_client(DB_Name, Client_Name),
	    send_reply(From, C),
	    client_db_loop(DB_Name);
	{From, client_pid, {Client_Name}} ->
	    Pid = client_pid(DB_Name, Client_Name),
	    send_reply(From, Pid),
	    client_db_loop(DB_Name);
	{From, client_monitor_pid, {Client_Name}} ->
	    Pid = client_monitor_pid(DB_Name, Client_Name),
	    send_reply(From, Pid),
	    client_db_loop(DB_Name);
	{From, recover, {S_Group_Name, Target_DB_Name, Source_DB_Name}} ->
	    spawn(fun() -> recover_db(S_Group_Name, From, Target_DB_Name, Source_DB_Name) end),
	    client_db_loop(DB_Name);
	{undefined, From, recovery_binary, Binary} ->
	    ets:insert(DB_Name, binary_to_term(Binary)),
	    if
		is_list(From) == true ->
		    send_reply(lists:last(From), {recovered, ok});
		true ->
		    send_reply(From, {recovered, ok})
	    end,
	    client_db_loop(DB_Name);
	{From, pass_binary} ->
	    Binary = term_to_binary(ets:tab2list(DB_Name)),
	    send_reply(From, Binary),
	    client_db_loop(DB_Name);
	{From, stop} ->
	    stop(DB_Name),
	    send_reply(From, {client_db_destroyed, ok});
	Other ->
	    io:format("Something failed at Client_DB. Received: ~p", [Other]),
	    client_db_loop(DB_Name)
    end.

%%---------------------------------------------------------------------
%% @doc
%% Creates a new ets table -named Table_Name- to store the different
%% clients active in the system.
%%
%% @spec create(Table_Name) -> Table_Name | {error, Error}
%% @end
%%---------------------------------------------------------------------
create(Table_Name) ->
    ets:new(Table_Name, [set, named_table]).

%%---------------------------------------------------------------------
%% @doc
%% Destroys ets table named Table_Name.
%%
%% @spec destroy(Table_Name) -> Table_Name | {error, Error}
%% @end
%%---------------------------------------------------------------------
destroy(Table_Name) ->
    ets:delete(Table_Name).

%%---------------------------------------------------------------------
%% @doc
%% Adds a client to the clients database.
%%
%% @spec add_client(Table_Name, Client_name, Client_Pid,
%%                  Client_Monitor_Pid) -> true | {error, Error}
%% @end
%%---------------------------------------------------------------------
add_client(Table_Name, Client_Name, Client_Pid, Client_Monitor_Pid) ->
    ets:insert(Table_Name, {Client_Name, Client_Pid, Client_Monitor_Pid}).

%%---------------------------------------------------------------------
%% @doc
%% Removes a client from the clients database.
%%
%% @spec remove_session(Table_Name, Client_name) -> true | {error, Error}
%% @end
%%---------------------------------------------------------------------
remove_client(Table_Name, Client_Name) ->
    ets:delete(Table_Name, Client_Name).

%%---------------------------------------------------------------------
%% @doc
%% Updates a client's Pid.
%%
%% @spec update_client_pid(Table_Name, Client_Monitor_Pid) ->
%%              true | {error, Error}
%% @end
%%---------------------------------------------------------------------
update_client_pid(Table_Name, Client_Name, New_Pid) ->
    ets:update_element(Table_Name, Client_Name, {2, New_Pid}).

%%---------------------------------------------------------------------
%% @doc
%% Updates a client's monitor Pid.
%%
%% @spec update_client_pid(Table_Name, Client_Monitor_Pid) ->
%%              true | {error, Error}
%% @end
%%---------------------------------------------------------------------
update_client_monitor_pid(Table_Name, Client_Name, New_Monitor_Pid) ->
    ets:update_element(Table_Name, Client_Name, {3, New_Monitor_Pid}).

%%---------------------------------------------------------------------
%% @doc
%% Returns the contents of the whole database as a list of lists, where
%% each of the nested lists is one client. (Not in use, only for debug
%% purposes
%%
%% @spec retrieve_db(Table_Name) ->
%%                  [[Client1], ..., [ClientK]] | {error, Error}
%% @end
%%---------------------------------------------------------------------
retrieve_db(Table_Name) ->
    ets:match(Table_Name, {'$0', '$1', '$2'}).

%%---------------------------------------------------------------------
%% @doc
%% Returns a list containing the data of the client passed as argument.
%% It does not delete the client from the db.
%%
%% @spec peak_client(Table_Name, Client_Monitor_Pid) ->
%%                       [Client_Name, Client_Monitor_Pid, Client] | []
%% @end
%%---------------------------------------------------------------------
peak_client(Table_Name, Client_Name) ->
    L = ets:lookup(Table_Name, Client_Name),
    case L of
	[] ->
	    L;
	[{Client_Name, Client_Pid, Client_Monitor}] ->
	    [Client_Name, Client_Pid, Client_Monitor]
    end.

%%---------------------------------------------------------------------
%% @doc
%% Returns a list containing the data of the client monitored by the
%% monitor that has the pid passed as argument.
%% It does not delete the client from the db.
%%
%% @spec peak_client_monitor(Table_Name, Client_Monitor_Pid) ->
%%                       [Client_Name, Client_Monitor_Pid, Client] | []
%% @end
%%---------------------------------------------------------------------
peak_client_monitor(Table_Name, Client_Monitor_Pid) ->
    L = ets:select(Table_Name, [{{'$0', '$1', '$2'},
				 [{'==', '$2', Client_Monitor_Pid}],
				 [['$0', '$1', '$2']]}]),
    case L == [] of
	true ->
	    L;
	false ->
	    lists:last(L)
    end.

%%---------------------------------------------------------------------
%% @doc
%% Deletes the client passed as argument from the database and returns
%% a list containing the data of the said client.
%%
%% @spec retrieve_client(Table_Name, Client_Monitor_Pid) ->
%%                       [Client_Monitor_Pid, Client] | {error, Error}
%% @end
%%---------------------------------------------------------------------
retrieve_client(Table_Name, Client_Name) ->
    C = peak_client(Table_Name, Client_Name),
    remove_client(Table_Name, Client_Name),
    C.

%%--------------------------------------------------------------------
%% @doc
%% Returns the Pid of the client passed as argument.
%%
%% @spec client_pid(Table_Name, Session_Name) -> Client_Pid | []
%% @end
%%--------------------------------------------------------------------
client_pid(Table_Name, Client_Name) ->
    L = ets:lookup(Table_Name, Client_Name),
    case L of
	[] ->
	    L;
	[{_,Client_Pid, _}] ->
	    Client_Pid
    end.

%%---------------------------------------------------------------------
%% @doc
%% Returns the Pid of the client monitor for a given client passed as
%% argument.
%%
%% @spec client_monitor_pid(Table_Name, Session_Name) ->
%%             Client_Monitor_Pid | []
%% @end
%%---------------------------------------------------------------------
client_monitor_pid(Table_Name, Client_Name)->
    L = ets:lookup(Table_Name, Client_Name),
    case L of
	[] ->
	    L;
	[{_,_,Monitor_Pid}] ->
	    Monitor_Pid
    end.

%%---------------------------------------------------------------------
%% @doc
%% Replicates the clients table specified as the Source argument, in a
%% new table with name Table_Name.
%%
%% @spec retrieve_server(Table_Name, Client_Monitor_Pid) -> 
%%                  true | {error, Error}
%% @end
%%---------------------------------------------------------------------
recover_db(S_Group_Name, From, Destination, Source) ->
    ets:safe_fixtable(Source, true),
    send_to_replica(S_Group_Name, Destination, {undefined, From, recovery_binary, term_to_binary(ets:tab2list(Source))}),
    ets:safe_fixtable(Source, false).

%%---------------------------------------------------------------------
%% @doc
%%     send_to_replica/3 implements a safe mechanism to send replies to
%%     remote databases.
%%
%% @spec send_to_replica(S_Group_Name, DB_Replica, Message) -> Message | ok
%% @end
%%---------------------------------------------------------------------
send_to_replica(S_Group_Name, DB_Replica, Message) ->
    case s_group:whereis_name(S_Group_Name, DB_Replica) of
	undefined ->
	    <<A:32, B:32, C:32>> = crypto:rand_bytes(12),
	    random:seed({A,B,C}),
	    {Own_Group, _Rubbish} = hd(s_group:own_s_groups()),
	    Broadcast_Message = {S_Group_Name, DB_Replica, Message},
	    broadcast_message(Own_Group, Broadcast_Message);
	Pid ->
	    Pid ! Message
    end.

%%--------------------------------------------------------------------
%% @doc
%%     broadcast_message/2 sends the message to a random relay to broadcast
%%     the message to the target database.
%%
%% @spec broadcast_message(S_Group_Name, Message) -> Message | ok 
%% @end
%%--------------------------------------------------------------------
broadcast_message(S_Group_Name, Message) ->
    Relay = string_to_atom("relay_" ++ integer_to_list(random:uniform(50))), %% <=== Change to the actual number of relays (currently 50).
    case s_group:whereis_name(S_Group_Name, Relay) of
	undefined ->
	    ok;
	Pid ->
	    Pid ! {Message, broadcast_message}
    end.

%%--------------------------------------------------------------------
%% @doc
%%     send_reply/2 implements a safe mechanism to send replies to
%%     remote databases without using s_group:whereis/2. It uses
%%     a kind of next-hop routing instead, following the pids of the
%%     relay and router recorded in the From field of the request
%%     message. This ensures that no extra connections are established
%%     when sending back the replies from the databases.
%%
%% @spec send_reply(Target, Reply) -> {reply_back, Next_Hops, Reply} |
%%                                    Reply | ok.
%% @end
%%--------------------------------------------------------------------
send_reply(Target, Reply) ->
    case Target of
	undefined ->
	    ok;
	[Pid|Next_Hops] ->
	    case rpc:pinfo(Pid, status) of
		undefined ->
		    {S_Group_Name, _Rubbish} = hd(s_group:own_s_groups()),
		    Relay = string_to_atom("relay_" ++ integer_to_list(random:uniform(50))), %% <=== Change to the actual number of relays (currently 50).
		    s_group:whereis_name(S_Group_Name, Relay) ! {reply_back, Next_Hops, Reply};
		_Status ->		    
		    Pid ! {reply_back, Next_Hops, Reply},
		    ok
	    end;
	Other when is_pid(Other) ->
	    Target ! Reply;
	Other ->
	    io:format("send_reply/2 received: ~p~n", [Other]),
	    ok
    end.

%%--------------------------------------------------------------------
%% @doc
%%     string_to_atom/1 takes a string and returns an atom, or an
%%     existing atom if that is the case.
%%
%% @spec string_to_atom(String) -> atom() | existing_atom()
%% @end
%%--------------------------------------------------------------------
string_to_atom(String) ->
    try list_to_existing_atom(String) of
	Val ->
	    Val
    catch
	error:_ ->
	    list_to_atom(String)
    end.
