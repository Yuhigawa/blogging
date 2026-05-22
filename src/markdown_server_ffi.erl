-module(markdown_server_ffi).
-export([read_text_file/1, list_dir/1]).

to_bin_string(Data) ->
    unicode:characters_to_binary(Data).

read_text_file(Filename) ->
    case file:read_file(Filename) of
        {ok, Data}            -> {ok, to_bin_string(Data)};
        {error, enoent}       -> {error, not_found};
        {error, eacces}       -> {error, permission};
        {error, Reason}       -> {error, {other, to_bin_string(io_lib:format("~p", [Reason]))}}
    end.

list_dir(Path) ->
    case file:list_dir(Path) of
        {ok, Entries}         -> {ok, [to_bin_string(E) || E <- Entries]};
        {error, enoent}       -> {error, not_found};
        {error, eacces}       -> {error, permission};
        {error, Reason}       -> {error, {other, to_bin_string(io_lib:format("~p", [Reason]))}}
    end.
