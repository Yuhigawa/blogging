-module(markdown_server_ffi).
-export([read_text_file/1, list_dir/1]).

to_bin(Data) ->
    case unicode:characters_to_binary(Data) of
        Bin when is_binary(Bin) -> {ok, Bin};
        _                       -> error
    end.

read_text_file(Filename) ->
    case file:read_file(Filename) of
        {ok, Data} ->
            case to_bin(Data) of
                {ok, Bin} -> {ok, Bin};
                error     -> {error, {other, <<"encoding error">>}}
            end;
        {error, enoent}  -> {error, not_found};
        {error, eacces}  -> {error, permission};
        {error, Reason}  ->
            case to_bin(io_lib:format("~p", [Reason])) of
                {ok, Bin} -> {error, {other, Bin}};
                error     -> {error, {other, <<"unknown">>}}
            end
    end.

list_dir(Path) ->
    case file:list_dir(Path) of
        {ok, Entries} ->
            case convert_entries(Entries, []) of
                {ok, Bins} -> {ok, Bins};
                error      -> {error, {other, <<"encoding error">>}}
            end;
        {error, enoent}  -> {error, not_found};
        {error, eacces}  -> {error, permission};
        {error, Reason}  ->
            case to_bin(io_lib:format("~p", [Reason])) of
                {ok, Bin} -> {error, {other, Bin}};
                error     -> {error, {other, <<"unknown">>}}
            end
    end.

convert_entries([], Acc) ->
    {ok, lists:reverse(Acc)};
convert_entries([E | Rest], Acc) ->
    case to_bin(E) of
        {ok, Bin} -> convert_entries(Rest, [Bin | Acc]);
        error     -> error
    end.
