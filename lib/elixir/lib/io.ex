# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

defmodule IO do
  @moduledoc ~S"""
  Functions handling input/output (IO).

  Many functions in this module expect an IO device as an argument.
  An IO device must be a PID or an atom representing a process.
  For convenience, Elixir provides `:stdio` and `:stderr` as
  shortcuts to Erlang's `:standard_io` and `:standard_error`.

  The majority of the functions expect chardata. In case another type is given,
  functions will convert those types to string via the `String.Chars` protocol
  (as shown in typespecs). For more information on chardata, see the
  "IO data" section below.

  The functions of this module use UNIX-style naming where possible.

  ## IO devices

  An IO device may be an atom or a PID. In case it is an atom,
  the atom must be the name of a registered process. In addition,
  Elixir provides two shortcuts:

    * `:stdio` - a shortcut for `:standard_io`, which maps to
      the current `Process.group_leader/0` in Erlang

    * `:stderr` - a shortcut for the named process `:standard_error`
      provided in Erlang

  IO devices maintain their position, which means subsequent calls to any
  reading or writing functions will start from the place where the device
  was last accessed. The position of files can be changed using the
  `:file.position/2` function.

  ## IO data

  IO data is a data type that can be used as a more efficient alternative to binaries
  in certain situations.

  A term of type **IO data** is a binary or a list containing bytes (integers within the `0..255` range)
  or nested IO data. The type is recursive. Let's see an example of one of
  the possible IO data representing the binary `"hello"`:

      [?h, "el", ["l", [?o]]]

  The built-in `t:iodata/0` type is defined in terms of `t:iolist/0`. An IO list is
  the same as IO data but it doesn't allow for a binary at the top level (but binaries
  are still allowed in the list itself).

  ### Use cases for IO data

  IO data exists because often you need to do many append operations
  on smaller chunks of binaries in order to create a bigger binary. However, in
  Erlang and Elixir concatenating binaries will copy the concatenated binaries
  into a new binary.

      def email(username, domain) do
        username <> "@" <> domain
      end

  In this function, creating the email address will copy the `username` and `domain`
  binaries. Now imagine you want to use the resulting email inside another binary:

      def welcome_message(name, username, domain) do
        "Welcome #{name}, your email is: #{email(username, domain)}"
      end

      IO.puts(welcome_message("Meg", "meg", "example.com"))
      #=> "Welcome Meg, your email is: meg@example.com"

  Every time you concatenate binaries or use interpolation (`#{}`) you are making
  copies of those binaries. However, in many cases you don't need the complete
  binary while you create it, but only at the end to print it out or send it
  somewhere. In such cases, you can construct the binary by creating IO data:

      def email(username, domain) do
        [username, ?@, domain]
      end

      def welcome_message(name, username, domain) do
        ["Welcome ", name, ", your email is: ", email(username, domain)]
      end

      IO.puts(welcome_message("Meg", "meg", "example.com"))
      #=> "Welcome Meg, your email is: meg@example.com"

  Building IO data is cheaper than concatenating binaries. Concatenating multiple
  pieces of IO data just means putting them together inside a list since IO data
  can be arbitrarily nested, and that's a cheap and efficient operation. Most of
  the IO-based APIs, such as `:gen_tcp` and `IO`, receive IO data and write it
  to the socket directly without converting it to binary.

  One drawback of IO data is that you can't do things like pattern match on the
  first part of a piece of IO data like you can with a binary, because you usually
  don't know the shape of the IO data. In those cases, you may need to convert it
  to a binary by calling `iodata_to_binary/1`, which is reasonably efficient
  since it's implemented natively in C. Other functionality, like computing the
  length of IO data, can be computed directly on the iodata by calling `iodata_length/1`.

  ### Chardata

  Erlang and Elixir also have the idea of `t:chardata/0`. Chardata is very
  similar to IO data: the only difference is that integers in IO data represent
  bytes while integers in chardata represent Unicode code points. Bytes
  (`t:byte/0`) are integers within the `0..255` range, while Unicode code points
  (`t:char/0`) are integers within the `0..0x10FFFF` range. The `IO` module provides
  the `chardata_to_string/1` function for chardata as the "counter-part" of the
  `iodata_to_binary/1` function for IO data.

  If you try to use `iodata_to_binary/1` on chardata, it will result in an
  argument error. For example, let's try to put a code point that is not
  representable with one byte, like `?π`, inside IO data:

      IO.iodata_to_binary(["The symbol for pi is: ", ?π])
      #=> ** (ArgumentError) argument error

  If we use chardata instead, it will work as expected:

      iex> IO.chardata_to_string(["The symbol for pi is: ", ?π])
      "The symbol for pi is: π"

  """

  @type device :: atom | pid
  @type nodata :: {:error, term} | :eof
  @type chardata :: String.t() | maybe_improper_list(char | chardata, String.t() | [])

  @type inspect_opts :: [Inspect.Opts.new_opt() | {:label, term}]

  @typedoc """
  Stacktrace information as keyword options for `warn/2`.

  At least `:file` is required. Other options are optional and used
  to provide more precise location information.
  """
  @type warn_stacktrace_opts :: [
          file: String.t(),
          line: pos_integer(),
          column: pos_integer(),
          module: module(),
          function: {atom(), arity()}
        ]

  defguardp is_device(term) when is_atom(term) or is_pid(term)
  defguardp is_iodata(data) when is_list(data) or is_binary(data)

  @doc ~S"""
  Reads from the IO `device`.

  The `device` is iterated as specified by the `line_or_chars` argument:

    * if `line_or_chars` is an integer, it represents a number of bytes. The device is
      iterated by that number of bytes. This should be the preferred mode for reading
      non-textual inputs.

    * if `line_or_chars` is `:line`, the device is iterated line by line.
      CRLF newlines  ("\r\n") are automatically normalized to "\n".

    * if `line_or_chars` is `:eof` (since v1.13), the device is iterated until `:eof`.
      If the device is already at the end, it returns `:eof` itself.

  It returns:

    * `data` - the output characters

    * `:eof` - end of file was encountered

    * `{:error, reason}` - other (rare) error condition;
      for instance, `{:error, :estale}` if reading from an
      NFS volume

  """
  @spec read(device, :eof | :line | non_neg_integer) :: chardata | nodata
  def read(device \\ :stdio, line_or_chars)

  # TODO: Remove me on v2.0
  def read(device, :all) do
    IO.warn("IO.read(device, :all) is deprecated, use IO.read(device, :eof) instead")

    with :eof <- read(device, :eof) do
      with [_ | _] = opts <- :io.getopts(device),
           false <- Keyword.get(opts, :binary, true) do
        ~c""
      else
        _ -> ""
      end
    end
  end

  def read(device, :eof) do
    getn(device, ~c"", :eof)
  end

  def read(device, :line) do
    :io.get_line(map_dev(device), ~c"")
  end

  def read(device, count) when is_integer(count) and count >= 0 do
    :io.get_chars(map_dev(device), ~c"", count)
  end

  @doc ~S"""
  Reads from the IO `device`. The operation is Unicode unsafe.

  The `device` is iterated as specified by the `line_or_chars` argument:

    * if `line_or_chars` is an integer, it represents a number of bytes. The device is
      iterated by that number of bytes. This should be the preferred mode for reading
      non-textual inputs.

    * if `line_or_chars` is `:line`, the device is iterated line by line.
      CRLF newlines  ("\r\n") are automatically normalized to "\n".

    * if `line_or_chars` is `:eof` (since v1.13), the device is iterated until `:eof`.
      If the device is already at the end, it returns `:eof` itself.

  It returns:

    * `data` - the output bytes

    * `:eof` - end of file was encountered

    * `{:error, reason}` - other (rare) error condition;
      for instance, `{:error, :estale}` if reading from an
      NFS volume

  Note: do not use this function on IO devices in Unicode mode
  as it will return the wrong result.
  """
  @spec binread(device, :eof | :line | non_neg_integer) :: iodata | nodata
  def binread(device \\ :stdio, line_or_chars)

  # TODO: Remove me on v2.0
  def binread(device, :all) do
    IO.warn("IO.binread(device, :all) is deprecated, use IO.binread(device, :eof) instead")
    with :eof <- binread(device, :eof), do: ""
  end

  def binread(device, :eof) do
    binread_eof(map_dev(device), "")
  end

  def binread(device, :line) do
    case :file.read_line(map_dev(device)) do
      {:ok, data} -> data
      other -> other
    end
  end

  def binread(device, count) when is_integer(count) and count >= 0 do
    case :file.read(map_dev(device), count) do
      {:ok, data} -> data
      other -> other
    end
  end

  @read_all_size 4096
  defp binread_eof(mapped_dev, acc) do
    case :file.read(mapped_dev, @read_all_size) do
      {:ok, data} -> binread_eof(mapped_dev, acc <> data)
      :eof -> if acc == "", do: :eof, else: acc
      other -> other
    end
  end

  @doc """
  Writes `chardata` to the given `device`.

  By default, the `device` is the standard output.

  ## Examples

      IO.write("sample")
      #=> sample

      IO.write(:stderr, "error")
      #=> error

  """
  @spec write(device, chardata | String.Chars.t()) :: :ok
  def write(device \\ :stdio, chardata) do
    :io.put_chars(map_dev(device), to_chardata(chardata))
  end

  @doc """
  Writes `iodata` to the given `device`.

  This operation is meant to be used with "raw" devices
  that are started without an encoding. The given `iodata`
  is written as is to the device, without conversion. For
  more information on IO data, see the "IO data" section in
  the module documentation.

  Use `write/2` for devices with encoding.

  Important: do **not** use this function on IO devices in
  Unicode mode as it will write the wrong data. In particular,
  the standard IO device is set to Unicode by default, so writing
  to stdio with this function will likely result in the wrong data
  being sent down the wire.
  """
  @spec binwrite(device, iodata) :: :ok
  def binwrite(device \\ :stdio, iodata) when is_iodata(iodata) do
    with {:error, reason} <- :file.write(map_dev(device), iodata) do
      :erlang.error(reason)
    end
  end

  @doc """
  Writes `item` to the given `device`, similar to `write/2`,
  but adds a newline at the end.

  By default, the `device` is the standard output. It returns `:ok`
  if it succeeds.

  Trivia: `puts` is shorthand for `put string`.

  ## Examples

      IO.puts("Hello World!")
      #=> Hello World!

      IO.puts(:stderr, "error")
      #=> error

  """
  @spec puts(device, chardata | String.Chars.t()) :: :ok
  def puts(device \\ :stdio, item) when is_device(device) do
    :io.put_chars(map_dev(device), [to_chardata(item), ?\n])
  end

  @doc """
  Writes a `message` to stderr, along with the given `stacktrace_info`.

  The `stacktrace_info` must be one of:

    * a `__STACKTRACE__`, where all entries in the stacktrace will be
      included in the error message

    * a `Macro.Env` structure (since v1.14.0), where a single stacktrace
      entry from the compilation environment will be used

    * a keyword list with at least the `:file` option representing
      a single stacktrace entry (since v1.14.0). The `:line`, `:column`,
      `:module`, and `:function` options are also supported

  This function notifies the compiler a warning was printed
  and emits a compiler diagnostic (`t:Code.diagnostic/1`).
  The diagnostic will include precise file and location information
  if a `Macro.Env` is given or those values have been passed as
  keyword list, but not for stacktraces, as they are often imprecise.

  It returns `:ok` if it succeeds.

  ## Examples

      IO.warn("variable bar is unused", module: MyApp, function: {:main, 1}, line: 4, file: "my_app.ex")
      #=> warning: variable bar is unused
      #=>   my_app.ex:4: MyApp.main/1

  """
  @spec warn(
          chardata | String.Chars.t(),
          Exception.stacktrace() | warn_stacktrace_opts() | Macro.Env.t()
        ) ::
          :ok
  def warn(message, stacktrace_info)

  def warn(message, %Macro.Env{line: line, file: file} = env) do
    message = to_chardata(message)

    :elixir_errors.emit_diagnostic(:warning, line, file, message, Macro.Env.stacktrace(env),
      read_snippet: true
    )
  end

  def warn(message, [{_, _} | _] = keyword) do
    if file = keyword[:file] do
      line = keyword[:line]
      column = keyword[:column]
      position = if line && column, do: {line, column}, else: line
      message = to_chardata(message)

      stacktrace =
        Macro.Env.stacktrace(%{
          __ENV__
          | module: keyword[:module],
            function: keyword[:function],
            line: line,
            file: file
        })

      :elixir_errors.emit_diagnostic(:warning, position, file, message, stacktrace,
        read_snippet: true
      )
    else
      warn(message, [])
    end
  end

  def warn(message, []) do
    message = to_chardata(message)
    :elixir_errors.emit_diagnostic(:warning, 0, nil, message, [], read_snippet: false)
  end

  def warn(message, [{_, _, _, _} | _] = stacktrace) do
    message = to_chardata(message)
    :elixir_errors.emit_diagnostic(:warning, 0, nil, message, stacktrace, read_snippet: false)
  end

  @doc false
  def warn_once(key, message, stacktrace_drop_levels) do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    stacktrace = Enum.drop(stacktrace, stacktrace_drop_levels)

    if :elixir_config.warn(key, stacktrace) do
      warn(message.(), stacktrace)
    else
      :ok
    end
  end

  @doc """
  Writes a `message` to stderr, along with the current stacktrace.

  It returns `:ok` if it succeeds.

  Do not call this function at the tail of another function. Due to tail
  call optimization, a stacktrace entry would not be added and the
  stacktrace would be incorrectly trimmed. Therefore make sure at least
  one expression (or an atom such as `:ok`) follows the `IO.warn/1` call.

  ## Examples

      IO.warn("variable bar is unused")
      #=> warning: variable bar is unused
      #=>   (iex) evaluator.ex:108: IEx.Evaluator.eval/4

  """
  @spec warn(chardata | String.Chars.t()) :: :ok
  def warn(message) do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    warn(message, Enum.drop(stacktrace, 2))
  end

  @doc """
  Inspects and writes the given `item` to the standard output.

  It's important to note that it returns the given `item` unchanged.
  This makes it possible to "spy" on values by inserting an
  `IO.inspect/2` call almost anywhere in your code, for example,
  in the middle of a pipeline.

  It enables pretty printing by default with width of
  80 characters. The width can be changed by explicitly
  passing the `:width` option.

  The output can be decorated with a label, by providing the `:label`
  option to easily distinguish it from other `IO.inspect/2` calls.
  The label will be printed before the inspected `item`.

  See `Inspect.Opts` for a full list of remaining formatting options.
  To print to other IO devices, see `IO.inspect/3`

  ## Examples

  The following code:

      IO.inspect(<<0, 1, 2>>, width: 40)

  Prints:

      <<0, 1, 2>>

  You can use the `:label` option to decorate the output:

      IO.inspect(1..100, label: "a wonderful range")

  Prints:

      a wonderful range: 1..100

  Inspect truncates large inputs by default. The `:printable_limit` controls
  the limit for strings and other string-like constructs (such as charlists):

      "abc"
      |> String.duplicate(9001)
      |> IO.inspect(printable_limit: :infinity)

  For containers such as lists, maps, and tuples, the number of entries
  is managed by the `:limit` option:

      1..100
      |> Enum.map(& {&1, &1})
      |> Enum.into(%{})
      |> IO.inspect(limit: :infinity)

  """
  @spec inspect(item, inspect_opts) :: item when item: var
  def inspect(item, opts \\ []) do
    inspect(:stdio, item, opts)
  end

  @doc """
  Inspects `item` according to the given options using the IO `device`.

  See `inspect/2` for a full list of options.
  """
  @spec inspect(device, item, inspect_opts) :: item when item: var
  def inspect(device, item, opts) when is_device(device) and is_list(opts) do
    label = if label = opts[:label], do: [to_chardata(label), ": "], else: []
    opts = Inspect.Opts.new(opts)
    doc = Inspect.Algebra.group(Inspect.Algebra.to_doc(item, opts))
    chardata = Inspect.Algebra.format(doc, opts.width)
    puts(device, [label, chardata])
    item
  end

  @doc """
  Gets a number of bytes from IO device `:stdio`.

  If `:stdio` is a Unicode device, `count` implies
  the number of Unicode code points to be retrieved.
  Otherwise, `count` is the number of raw bytes to be retrieved.

  See `IO.getn/3` for a description of return values.
  """
  @spec getn(
          device | chardata | String.Chars.t(),
          pos_integer | :eof | chardata | String.Chars.t()
        ) ::
          chardata | nodata
  def getn(prompt, count \\ 1)

  def getn(prompt, :eof) do
    getn(:stdio, prompt, :eof)
  end

  def getn(prompt, count) when is_integer(count) and count > 0 do
    getn(:stdio, prompt, count)
  end

  def getn(device, prompt) when not is_integer(prompt) do
    getn(device, prompt, 1)
  end

  @doc """
  Gets a number of bytes from the IO `device`.

  If the IO `device` is a Unicode device, `count` implies
  the number of Unicode code points to be retrieved.
  Otherwise, `count` is the number of raw bytes to be retrieved.

  It returns:

    * `data` - the input characters

    * `:eof` - end of file was encountered

    * `{:error, reason}` - other (rare) error condition;
      for instance, `{:error, :estale}` if reading from an
      NFS volume

  """
  @spec getn(device, chardata | String.Chars.t(), pos_integer | :eof) :: chardata | nodata
  def getn(device, prompt, :eof) do
    getn_eof(map_dev(device), to_chardata(prompt), [])
  end

  def getn(device, prompt, count) when is_integer(count) and count > 0 do
    :io.get_chars(map_dev(device), to_chardata(prompt), count)
  end

  defp getn_eof(device, prompt, acc) do
    case :io.get_line(device, prompt) do
      line when is_binary(line) or is_list(line) -> getn_eof(device, ~c"", [line | acc])
      :eof -> wrap_eof(:lists.reverse(acc))
      other -> other
    end
  end

  defp wrap_eof([h | _] = acc) when is_binary(h), do: IO.iodata_to_binary(acc)
  defp wrap_eof([h | _] = acc) when is_list(h), do: :lists.flatten(acc)
  defp wrap_eof([]), do: :eof

  @doc ~S"""
  Reads a line from the IO `device`.

  It returns:

    * `data` - the characters in the line terminated
      by a line-feed (LF) or end of file (EOF)

    * `:eof` - end of file was encountered

    * `{:error, reason}` - other (rare) error condition;
      for instance, `{:error, :estale}` if reading from an
      NFS volume

  Trivia: `gets` is shorthand for `get string`.

  ## Examples

  To display "What is your name?" as a prompt and await user input:

      IO.gets("What is your name?\n")

  """
  @spec gets(device, chardata | String.Chars.t()) :: chardata | nodata
  def gets(device \\ :stdio, prompt) do
    :io.get_line(map_dev(device), to_chardata(prompt))
  end

  @doc """
  Returns a line-based `IO.Stream` on `:stdio`.

  This is equivalent to:

      IO.stream(:stdio, :line)

  """
  @doc since: "1.12.0"
  @spec stream() :: Enumerable.t(String.t())
  def stream, do: stream(:stdio, :line)

  @doc ~S"""
  Converts the IO `device` into an `IO.Stream`.

  An `IO.Stream` implements both `Enumerable` and
  `Collectable`, allowing it to be used for both read
  and write.

  The `device` is iterated by the given number of characters
  or line by line if `:line` is given. In case `:line` is given,
  "\r\n" is automatically normalized to "\n".

  This reads from the IO as UTF-8. Check out
  `IO.binstream/2` to handle the IO as a raw binary.

  Note that an IO stream has side effects and every time
  you go over the stream you may get different results.

  `stream/0` has been introduced in Elixir v1.12.0,
  while `stream/2` has been available since v1.0.0.

  ## Examples

  Here is an example on how we mimic an echo server
  from the command line:

      Enum.each(IO.stream(:stdio, :line), &IO.write(&1))

  Another example where you might want to collect a user input
  every new line and break on an empty line, followed by removing
  redundant new line characters (`"\n"`):

      IO.stream(:stdio, :line)
      |> Enum.take_while(&(&1 != "\n"))
      |> Enum.map(&String.replace(&1, "\n", ""))

  """
  @spec stream(device, :line | pos_integer) :: Enumerable.t()
  def stream(device \\ :stdio, line_or_codepoints)
      when line_or_codepoints == :line
      when is_integer(line_or_codepoints) and line_or_codepoints > 0 do
    IO.Stream.__build__(map_dev(device), false, line_or_codepoints)
  end

  @doc """
  Returns a raw, line-based `IO.Stream` on `:stdio`. The operation is Unicode unsafe.

  This is equivalent to:

      IO.binstream(:stdio, :line)

  """
  @doc since: "1.12.0"
  @spec binstream() :: Enumerable.t(binary)
  def binstream, do: binstream(:stdio, :line)

  @doc ~S"""
  Converts the IO `device` into an `IO.Stream`. The operation is Unicode unsafe.

  An `IO.Stream` implements both `Enumerable` and
  `Collectable`, allowing it to be used for both read
  and write.

  The `device` is iterated by the given number of bytes or line
  by line if `:line` is given. In case `:line` is given, "\r\n"
  is automatically normalized to "\n". Passing the number of bytes
  should be the preferred mode for reading non-textual inputs.

  Note that an IO stream has side effects and every time
  you go over the stream you may get different results.

  This reads from the IO device as a raw binary. Therefore,
  do not use this function on IO devices in Unicode mode as
  it will return the wrong result.

  `binstream/0` has been introduced in Elixir v1.12.0,
  while `binstream/2` has been available since v1.0.0.
  """
  @spec binstream(device, :line | pos_integer) :: Enumerable.t()
  def binstream(device \\ :stdio, line_or_bytes)
      when line_or_bytes == :line
      when is_integer(line_or_bytes) and line_or_bytes > 0 do
    IO.Stream.__build__(map_dev(device), true, line_or_bytes)
  end

  @doc """
  Converts chardata into a string.

  For more information about chardata, see the ["Chardata"](#module-chardata)
  section in the module documentation.

  In case the conversion fails, it raises an `UnicodeConversionError`.
  If a string is given, it returns the string itself.

  ## Examples

      iex> IO.chardata_to_string([0x00E6, 0x00DF])
      "æß"

      iex> IO.chardata_to_string([0x0061, "bc"])
      "abc"

      iex> IO.chardata_to_string("string")
      "string"

  """
  @spec chardata_to_string(chardata) :: String.t()
  def chardata_to_string(chardata)

  def chardata_to_string(string) when is_binary(string) do
    string
  end

  def chardata_to_string(list) when is_list(list) do
    List.to_string(list)
  end

  @doc """
  Converts IO data into a binary

  The operation is Unicode unsafe.

  Note that this function treats integers in the given IO data as
  raw bytes and does not perform any kind of encoding conversion.
  If you want to convert from a charlist to a UTF-8-encoded string,
  use `chardata_to_string/1` instead. For more information about
  IO data and chardata, see the ["IO data"](#module-io-data) section in the
  module documentation.

  If this function receives a binary, the same binary is returned.

  Inlined by the compiler.

  ## Examples

      iex> bin1 = <<1, 2, 3>>
      iex> bin2 = <<4, 5>>
      iex> bin3 = <<6>>
      iex> IO.iodata_to_binary([bin1, 1, [2, 3, bin2], 4 | bin3])
      <<1, 2, 3, 1, 2, 3, 4, 5, 4, 6>>

      iex> bin = <<1, 2, 3>>
      iex> IO.iodata_to_binary(bin)
      <<1, 2, 3>>

  """
  @spec iodata_to_binary(iodata) :: binary
  def iodata_to_binary(iodata) do
    :erlang.iolist_to_binary(iodata)
  end

  @doc """
  Returns the size of an IO data.

  For more information about IO data, see the ["IO data"](#module-io-data)
  section in the module documentation.

  Inlined by the compiler.

  ## Examples

      iex> IO.iodata_length([1, 2 | <<3, 4>>])
      4

  """
  @spec iodata_length(iodata) :: non_neg_integer
  def iodata_length(iodata) do
    :erlang.iolist_size(iodata)
  end

  @doc false
  def each_stream(device, line_or_codepoints) do
    case read(device, line_or_codepoints) do
      :eof ->
        {:halt, device}

      {:error, reason} ->
        raise IO.StreamError, reason: reason

      data ->
        {[data], device}
    end
  end

  @doc false
  def each_binstream(device, line_or_chars) do
    case binread(device, line_or_chars) do
      :eof ->
        {:halt, device}

      {:error, reason} ->
        raise IO.StreamError, reason: reason

      data ->
        {[data], device}
    end
  end

  @compile {:inline, map_dev: 1, to_chardata: 1}

  # Map the Elixir names for standard IO and error to Erlang names
  defp map_dev(:stdio), do: :standard_io
  defp map_dev(:stderr), do: :standard_error
  defp map_dev(other) when is_atom(other) or is_pid(other) or is_tuple(other), do: other

  defp to_chardata(list) when is_list(list), do: list
  defp to_chardata(other), do: to_string(other)
end
