# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

defmodule Protocol do
  @moduledoc ~S"""
  Reference and functions for working with protocols.

  A protocol specifies an API that should be defined by its
  implementations. A protocol is defined with `Kernel.defprotocol/2`
  and its implementations with `Kernel.defimpl/3`.

  ## Example

  In Elixir, we have two nouns for checking how many items there
  are in a data structure: `length` and `size`.  `length` means the
  information must be computed. For example, `length(list)` needs to
  traverse the whole list to calculate its length. On the other hand,
  `tuple_size(tuple)` and `byte_size(binary)` do not depend on the
  tuple and binary size as the size information is precomputed in
  the data structure.

  Although Elixir includes specific functions such as `tuple_size`,
  `binary_size` and `map_size`, sometimes we want to be able to
  retrieve the size of a data structure regardless of its type.
  In Elixir we can write polymorphic code, i.e. code that works
  with different shapes/types, by using protocols. A size protocol
  could be implemented as follows:

      defprotocol Size do
        @doc "Calculates the size (and not the length!) of a data structure"
        def size(data)
      end

  Now that the protocol can be implemented for every data structure
  the protocol may have a compliant implementation for:

      defimpl Size, for: BitString do
        def size(binary), do: byte_size(binary)
      end

      defimpl Size, for: Map do
        def size(map), do: map_size(map)
      end

      defimpl Size, for: Tuple do
        def size(tuple), do: tuple_size(tuple)
      end

  Finally, we can use the `Size` protocol to call the correct implementation:

      Size.size({1, 2})
      # => 2
      Size.size(%{key: :value})
      # => 1

  Note that we didn't implement it for lists as we don't have the
  `size` information on lists, rather its value needs to be
  computed with `length`.

  The data structure you are implementing the protocol for
  must be the first argument to all functions defined in the
  protocol.

  It is possible to implement protocols for all Elixir types:

    * Structs (see the "Protocols and Structs" section below)
    * `Tuple`
    * `Atom`
    * `List`
    * `BitString`
    * `Integer`
    * `Float`
    * `Function`
    * `PID`
    * `Map`
    * `Port`
    * `Reference`
    * `Any` (see the "Fallback to `Any`" section below)

  ## Protocols and Structs

  The real benefit of protocols comes when mixed with structs.
  For instance, Elixir ships with many data types implemented as
  structs, like `MapSet`. We can implement the `Size` protocol
  for those types as well:

      defimpl Size, for: MapSet do
        def size(map_set), do: MapSet.size(map_set)
      end

  When implementing a protocol for a struct, the `:for` option can
  be omitted if the `defimpl/3` call is inside the module that defines
  the struct:

      defmodule User do
        defstruct [:email, :name]

        defimpl Size do
          # two fields
          def size(%User{}), do: 2
        end
      end

  If a protocol implementation is not found for a given type,
  invoking the protocol will raise unless it is configured to
  fall back to `Any`. Conveniences for building implementations
  on top of existing ones are also available, look at `defstruct/1`
  for more information about deriving protocols.

  ## Fallback to `Any`

  In some cases, it may be convenient to provide a default
  implementation for all types. This can be achieved by setting
  the `@fallback_to_any` attribute to `true` in the protocol
  definition:

      defprotocol Size do
        @fallback_to_any true
        def size(data)
      end

  The `Size` protocol can now be implemented for `Any`:

      defimpl Size, for: Any do
        def size(_), do: 0
      end

  Although the implementation above is arguably not a reasonable
  one. For example, it makes no sense to say a PID or an integer
  have a size of `0`. That's one of the reasons why `@fallback_to_any`
  is an opt-in behavior. For the majority of protocols, raising
  an error when a protocol is not implemented is the proper behavior.

  ## Multiple implementations

  Protocols can also be implemented for multiple types at once:

      defprotocol Reversible do
        def reverse(term)
      end

      defimpl Reversible, for: [Map, List] do
        def reverse(term), do: Enum.reverse(term)
      end

  Inside `defimpl/3`, you can use `@protocol` to access the protocol
  being implemented and `@for` to access the module it is being
  defined for.

  ## Types

  Defining a protocol automatically defines a zero-arity type named `t`, which
  can be used as follows:

      @spec print_size(Size.t()) :: :ok
      def print_size(data) do
        result =
          case Size.size(data) do
            0 -> "data has no items"
            1 -> "data has one item"
            n -> "data has #{n} items"
          end

        IO.puts(result)
      end

  The `@spec` above expresses that all types allowed to implement the
  given protocol are valid argument types for the given function.

  ## Configuration

  The following module attributes are available to configure a protocol:

    * `@fallback_to_any` - when true, enables protocol dispatch to
      fallback to any

    * `@undefined_impl_description` - a string with additional description
      to be used on `Protocol.UndefinedError` when looking up the implementation
      fails. This option is only applied if `@fallback_to_any` is not set to true

  ## Consolidation

  In order to speed up protocol dispatching, whenever all protocol implementations
  are known up-front, typically after all Elixir code in a project is compiled,
  Elixir provides a feature called *protocol consolidation*. Consolidation directly
  links protocols to their implementations in a way that invoking a function from a
  consolidated protocol is equivalent to invoking two remote functions - one to
  identify the correct implementation, and another to call the implementation.

  Protocol consolidation is applied by default to all Mix projects during compilation.
  This may be an issue during test. For instance, if you want to implement a protocol
  during test, the implementation will have no effect, as the protocol has already been
  consolidated. One possible solution is to include compilation directories that are
  specific to your test environment in your mix.exs:

      def project do
        ...
        elixirc_paths: elixirc_paths(Mix.env())
        ...
      end

      defp elixirc_paths(:test), do: ["lib", "test/support"]
      defp elixirc_paths(_), do: ["lib"]

  And then you can define the implementations specific to the test environment
  inside `test/support/some_file.ex`.

  Another approach is to disable protocol consolidation during tests in your
  mix.exs:

      def project do
        ...
        consolidate_protocols: Mix.env() != :test
        ...
      end

  If you are using `Mix.install/2`, you can do by passing the `consolidate_protocols`
  option:

      Mix.install(
        deps,
        consolidate_protocols: false
      )

  Although doing so is not recommended as it may affect the performance of
  your code.

  Finally, note all protocols are compiled with `debug_info` set to `true`,
  regardless of the option set by the `elixirc` compiler. The debug info is
  used for consolidation and it is removed after consolidation unless
  globally set.
  """

  @doc """
  A function available in all protocol definitions that returns protocol metadata.
  """
  @callback __protocol__(:consolidated?) :: boolean()
  @callback __protocol__(:functions) :: [{atom(), arity()}]
  @callback __protocol__(:impls) :: {:consolidated, [module()]} | :not_consolidated
  @callback __protocol__(:module) :: module()

  @doc """
  A function available in all protocol definitions that returns the implementation
  for the given `term` or nil.

  If `@fallback_to_any` is true, `nil` is never returned.
  """
  @callback impl_for(term) :: module() | nil

  @doc """
  A function available in all protocol definitions that returns the implementation
  for the given `term` or raises.

  If `@fallback_to_any` is true, it never raises.
  """
  @callback impl_for!(term) :: module()

  @doc """
  An optional callback to be implemented by protocol authors for custom deriving.

  It must return a quoted expression that implements the protocol for the given module.

  See `Protocol.derive/3` for an example.
  """
  @macrocallback __deriving__(module(), term()) :: Macro.t()

  @optional_callbacks __deriving__: 2

  @doc false
  defmacro def(signature)

  defmacro def({_, _, args}) when args == [] or is_atom(args) do
    raise ArgumentError, "protocol functions expect at least one argument"
  end

  defmacro def({name, _, args}) when is_atom(name) and is_list(args) do
    arity = length(args)

    type_args = :lists.map(fn _ -> quote(do: term) end, :lists.seq(2, arity))
    type_args = [quote(do: t) | type_args]

    to_var = fn pos -> Macro.var(String.to_atom("arg" <> Integer.to_string(pos)), __MODULE__) end

    call_args = :lists.map(to_var, :lists.seq(2, arity))
    call_args = [quote(do: term) | call_args]

    quote generated: true do
      name = unquote(name)
      arity = unquote(arity)

      @__functions__ [{name, arity} | @__functions__]

      # Generate a fake definition with the user
      # signature that will be used by docs
      Kernel.def(unquote(name)(unquote_splicing(args)))

      # Generate the actual implementation
      Kernel.def unquote(name)(unquote_splicing(call_args)) do
        impl_for!(term).unquote(name)(unquote_splicing(call_args))
      end

      # Copy spec as callback if possible,
      # otherwise generate a dummy callback
      Module.spec_to_callback(__MODULE__, {name, arity}) ||
        @callback unquote(name)(unquote_splicing(type_args)) :: term
    end
  end

  defmacro def(_) do
    raise ArgumentError, "invalid arguments for def inside defprotocol"
  end

  @doc """
  Checks if the given module is loaded and is protocol.

  Returns `:ok` if so, otherwise raises `ArgumentError`.
  """
  @spec assert_protocol!(module) :: :ok
  def assert_protocol!(module) do
    assert_protocol!(module, "")
  end

  defp assert_protocol!(module, extra) do
    try do
      Code.ensure_compiled!(module)
    rescue
      e in ArgumentError ->
        raise ArgumentError, e.message <> extra
    end

    try do
      module.__protocol__(:module)
    rescue
      UndefinedFunctionError ->
        raise ArgumentError, "#{inspect(module)} is not a protocol" <> extra
    end

    :ok
  end

  @doc """
  Checks if the given module is loaded and is an implementation
  of the given protocol.

  Returns `:ok` if so, otherwise raises `ArgumentError`.
  """
  @spec assert_impl!(module, module) :: :ok
  def assert_impl!(protocol, base) do
    assert_impl!(protocol, base, "")
  end

  defp assert_impl!(protocol, base, extra) do
    impl = __concat__(protocol, base)

    try do
      Code.ensure_compiled!(impl)
    rescue
      e in ArgumentError ->
        raise ArgumentError, e.message <> extra
    end

    try do
      impl.__impl__(:protocol)
    rescue
      UndefinedFunctionError ->
        raise ArgumentError, "#{inspect(impl)} is not an implementation of a protocol" <> extra
    else
      ^protocol ->
        :ok

      other ->
        raise ArgumentError,
              "expected #{inspect(impl)} to be an implementation of #{inspect(protocol)}" <>
                ", got: #{inspect(other)}" <> extra
    end
  end

  @doc """
  Derives the `protocol` for `module` with the given options.

  Every time you derive a protocol, Elixir will verify if the protocol
  has implemented the `c:Protocol.__deriving__/2` callback. If so,
  the callback will be invoked and it should define the implementation
  module. Otherwise an implementation that simply points to the `Any`
  implementation is automatically derived.

  ## Examples

      defprotocol Derivable do
        @impl true
        defmacro __deriving__(module, options) do
          # If you need to load struct metadata, you may call:
          # struct_info = Macro.struct_info!(module, __CALLER__)

          quote do
            defimpl Derivable, for: unquote(module) do
              def ok(arg) do
                {:ok, arg, unquote(options)}
              end
            end
          end
        end

        def ok(arg)
      end

  Once the protocol is defined, there are two ways it can be
  derived. The first is by using the `@derive` module attribute
  by the time you define the struct:

      defmodule ImplStruct do
        @derive [Derivable]
        defstruct a: 0, b: 0
      end

      Derivable.ok(%ImplStruct{})
      #=> {:ok, %ImplStruct{a: 0, b: 0}, []}

  If the struct has already been defined, you can call this macro:

      require Protocol
      Protocol.derive(Derivable, ImplStruct, :oops)
      Derivable.ok(%ImplStruct{a: 1, b: 1})
      #=> {:ok, %ImplStruct{a: 1, b: 1}, :oops}

  """
  defmacro derive(protocol, module, options \\ []) do
    quote do
      Protocol.__derive__([{unquote(protocol), unquote(options)}], unquote(module), __ENV__)
    end
  end

  ## Consolidation

  @doc """
  Extracts all protocols from the given paths.

  The paths can be either a charlist or a string. Internally
  they are worked on as charlists, so passing them as lists
  avoid extra conversion.

  Does not load any of the protocols.

  ## Examples

      # Get Elixir's ebin directory path and retrieve all protocols
      iex> path = Application.app_dir(:elixir, "ebin")
      iex> mods = Protocol.extract_protocols([path])
      iex> Enumerable in mods
      true

  """
  @spec extract_protocols([charlist | String.t()]) :: [atom]
  def extract_protocols(paths) do
    extract_matching_by_attribute(paths, [?E, ?l, ?i, ?x, ?i, ?r, ?.], fn module, attributes ->
      case attributes[:__protocol__] do
        [fallback_to_any: _] -> module
        _ -> nil
      end
    end)
  end

  @doc """
  Extracts all types implemented for the given protocol from
  the given paths.

  The paths can be either a charlist or a string. Internally
  they are worked on as charlists, so passing them as lists
  avoid extra conversion.

  Does not load any of the implementations.

  ## Examples

      # Get Elixir's ebin directory path and retrieve all protocols
      iex> path = Application.app_dir(:elixir, "ebin")
      iex> mods = Protocol.extract_impls(Enumerable, [path])
      iex> List in mods
      true

  """
  @spec extract_impls(module, [charlist | String.t()]) :: [atom]
  def extract_impls(protocol, paths) when is_atom(protocol) do
    prefix = Atom.to_charlist(protocol) ++ [?.]

    extract_matching_by_attribute(paths, prefix, fn _mod, attributes ->
      case attributes[:__impl__] do
        [protocol: ^protocol, for: for] -> for
        _ -> nil
      end
    end)
  end

  defp extract_matching_by_attribute(paths, prefix, callback) do
    for path <- paths,
        # Do not use protocols as they may be consolidating
        path = if(is_list(path), do: path, else: String.to_charlist(path)),
        file <- list_dir(path),
        mod = extract_from_file(path, file, prefix, callback),
        do: mod
  end

  defp list_dir(path) when is_list(path) do
    case :file.list_dir(path) do
      {:ok, files} -> files
      _ -> []
    end
  end

  defp extract_from_file(path, file, prefix, callback) do
    if :lists.prefix(prefix, file) and :filename.extension(file) == [?., ?b, ?e, ?a, ?m] do
      extract_from_beam(:filename.join(path, file), callback)
    end
  end

  defp extract_from_beam(file, callback) do
    case :beam_lib.chunks(file, [:attributes]) do
      {:ok, {module, [attributes: attributes]}} ->
        callback.(module, attributes)

      _ ->
        nil
    end
  end

  @doc """
  Returns `true` if the protocol was consolidated.
  """
  @spec consolidated?(module) :: boolean
  def consolidated?(protocol) do
    protocol.__protocol__(:consolidated?)
  end

  @doc """
  Receives a protocol and a list of implementations and
  consolidates the given protocol.

  Consolidation happens by changing the protocol `impl_for`
  in the abstract format to have fast lookup rules. Usually
  the list of implementations to use during consolidation
  are retrieved with the help of `extract_impls/2`.

  It returns the updated version of the protocol bytecode.
  If the first element of the tuple is `:ok`, it means
  the protocol was consolidated.

  A given bytecode or protocol implementation can be checked
  to be consolidated or not by analyzing the protocol
  attribute:

      Protocol.consolidated?(Enumerable)

  This function does not load the protocol at any point
  nor loads the new bytecode for the compiled module.
  However, each implementation must be available and
  it will be loaded.
  """
  @spec consolidate(module, [module]) ::
          {:ok, binary}
          | {:error, :not_a_protocol}
          | {:error, :no_beam_info}
  def consolidate(protocol, types) when is_atom(protocol) do
    # Ensure the types are sorted so the compiled beam is deterministic
    types = Enum.sort(types)

    with {:ok, any, definitions, signatures, compile_info} <- beam_protocol(protocol),
         {:ok, definitions, signatures} <-
           consolidate(protocol, any, definitions, signatures, types),
         do: compile(definitions, signatures, compile_info)
  end

  defp beam_protocol(protocol) do
    chunk_ids = [:debug_info, [?D, ?o, ?c, ?s]]
    opts = [:allow_missing_chunks]

    case :beam_lib.chunks(beam_file(protocol), chunk_ids, opts) do
      {:ok, {^protocol, [{:debug_info, debug_info} | chunks]}} ->
        {:debug_info_v1, _backend, {:elixir_v1, module_map, specs}} = debug_info
        %{attributes: attributes, definitions: definitions} = module_map

        # Protocols in precompiled archives may not have signatures, so we default to an empty map.
        # TODO: Remove this on Elixir v1.23.
        signatures = Map.get(module_map, :signatures, %{})

        chunks = :lists.filter(fn {_name, value} -> value != :missing_chunk end, chunks)
        chunks = :lists.map(fn {name, value} -> {List.to_string(name), value} end, chunks)

        case attributes[:__protocol__] do
          [fallback_to_any: any] ->
            {:ok, any, definitions, signatures, {module_map, specs, chunks}}

          _ ->
            {:error, :not_a_protocol}
        end

      _ ->
        {:error, :no_beam_info}
    end
  end

  defp beam_file(module) when is_atom(module) do
    case :code.which(module) do
      [_ | _] = file -> file
      _ -> module
    end
  end

  # Consolidate the protocol for faster implementations and fine-grained type information.
  defp consolidate(protocol, fallback_to_any?, definitions, signatures, types) do
    case List.keytake(definitions, {:__protocol__, 1}, 0) do
      {protocol_def, definitions} ->
        types = if fallback_to_any?, do: types, else: List.delete(types, Any)
        built_in_plus_any = [Any] ++ for {mod, _guard} <- built_in(), do: mod
        structs = types -- built_in_plus_any

        {impl_for, definitions} = List.keytake(definitions, {:impl_for, 1}, 0)
        {impl_for!, definitions} = List.keytake(definitions, {:impl_for!, 1}, 0)
        {struct_impl_for, definitions} = List.keytake(definitions, {:struct_impl_for, 1}, 0)

        protocol_funs = get_protocol_functions(protocol_def)

        protocol_def = change_protocol(protocol_def, types)
        impl_for = change_impl_for(impl_for, protocol, types)
        struct_impl_for = change_struct_impl_for(struct_impl_for, protocol, types, structs)
        new_signatures = new_signatures(definitions, protocol_funs, protocol, types)

        definitions = [protocol_def, impl_for, impl_for!, struct_impl_for] ++ definitions
        signatures = Enum.into(new_signatures, signatures)
        {:ok, definitions, signatures}

      nil ->
        {:error, :not_a_protocol}
    end
  end

  defp new_signatures(definitions, protocol_funs, protocol, types) do
    alias Module.Types.Descr

    clauses =
      types
      |> List.delete(Any)
      |> Enum.map(fn impl ->
        {[Module.Types.Of.impl(impl)], Descr.atom([__concat__(protocol, impl)])}
      end)

    {domain, impl_for, impl_for!} =
      case clauses do
        [] ->
          if Any in types do
            clauses = [{[Descr.term()], Descr.atom([__concat__(protocol, Any)])}]
            {Descr.term(), clauses, clauses}
          else
            {Descr.none(), [{[Descr.term()], Descr.atom([nil])}],
             [{[Descr.none()], Descr.none()}]}
          end

        _ ->
          domain =
            clauses
            |> Enum.map(fn {[domain], _} -> domain end)
            |> Enum.reduce(&Descr.union/2)

          not_domain = Descr.negation(domain)

          if Any in types do
            clauses =
              clauses ++ [{[not_domain], Descr.atom([__concat__(protocol, Any)])}]

            {Descr.term(), clauses, clauses}
          else
            {domain, clauses ++ [{[not_domain], Descr.atom([nil])}], clauses}
          end
      end

    new_signatures =
      for {{_fun, arity} = fun_arity, :def, _, _} <- definitions,
          fun_arity in protocol_funs do
        rest = List.duplicate(Descr.term(), arity - 1)
        {fun_arity, {:strong, nil, [{[domain | rest], Descr.dynamic()}]}}
      end

    [
      {{:impl_for, 1}, {:strong, [Descr.term()], impl_for}},
      {{:impl_for!, 1}, {:strong, [domain], impl_for!}}
    ] ++ new_signatures
  end

  defp get_protocol_functions({_name, _kind, _meta, clauses}) do
    Enum.find_value(clauses, fn
      {_meta, [:functions], [], clauses} -> clauses
      _ -> nil
    end) || raise "could not find protocol functions"
  end

  defp change_protocol({_name, _kind, meta, clauses}, types) do
    clauses =
      Enum.map(clauses, fn
        {meta, [:consolidated?], [], _} -> {meta, [:consolidated?], [], true}
        {meta, [:impls], [], _} -> {meta, [:impls], [], {:consolidated, types}}
        clause -> clause
      end)

    {{:__protocol__, 1}, :def, meta, clauses}
  end

  defp change_impl_for({_name, _kind, meta, _clauses}, protocol, types) do
    fallback = if Any in types, do: __concat__(protocol, Any)
    line = meta[:line]

    clauses =
      for {mod, guard} <- built_in(),
          mod in types,
          do: built_in_clause_for(mod, guard, protocol, meta, line)

    struct_clause = struct_clause_for(meta, line)
    fallback_clause = fallback_clause_for(fallback, protocol, meta)
    clauses = [struct_clause] ++ clauses ++ [fallback_clause]

    {{:impl_for, 1}, :def, meta, clauses}
  end

  defp change_struct_impl_for({_name, _kind, meta, _clauses}, protocol, types, structs) do
    fallback = if Any in types, do: __concat__(protocol, Any)
    clauses = for struct <- structs, do: each_struct_clause_for(struct, protocol, meta)
    clauses = clauses ++ [fallback_clause_for(fallback, protocol, meta)]

    {{:struct_impl_for, 1}, :defp, meta, clauses}
  end

  defp built_in_clause_for(mod, guard, protocol, meta, line) do
    x = {:x, [line: line, version: -1], __MODULE__}
    guard = quote(line: line, do: :erlang.unquote(guard)(unquote(x)))
    body = __concat__(protocol, mod)
    {meta, [x], [guard], body}
  end

  defp struct_clause_for(meta, line) do
    x = {:x, [line: line, version: -1], __MODULE__}
    head = quote(line: line, do: %{__struct__: unquote(x)})
    guard = quote(line: line, do: :erlang.is_atom(unquote(x)))
    body = quote(line: line, do: struct_impl_for(unquote(x)))
    {meta, [head], [guard], body}
  end

  defp each_struct_clause_for(struct, protocol, meta) do
    {meta, [struct], [], __concat__(protocol, struct)}
  end

  defp fallback_clause_for(value, _protocol, meta) do
    {meta, [quote(do: _)], [], value}
  end

  # Finally compile the module and emit its bytecode.
  defp compile(definitions, signatures, {module_map, specs, docs_chunk}) do
    # Protocols in precompiled archives may not have signatures, so we default to an empty map.
    # TODO: Remove this on Elixir v1.23.
    module_map = %{module_map | definitions: definitions} |> Map.put(:signatures, signatures)
    {:ok, :elixir_erl.consolidate(module_map, specs, docs_chunk)}
  end

  ## Definition callbacks

  @doc false
  def __protocol__(name, do: block) do
    quote do
      defmodule unquote(name) do
        @behaviour Protocol
        @before_compile Protocol

        # We don't allow function definition inside protocols
        import Kernel,
          except: [
            def: 1,
            def: 2,
            defdelegate: 2,
            defguard: 1,
            defguardp: 1,
            defstruct: 1,
            defexception: 1
          ]

        # Import the new `def` that is used by protocols
        import Protocol, only: [def: 1]

        # Compile with debug info for consolidation
        @compile :debug_info

        # Set up a clear slate to store defined functions
        @__functions__ []
        @fallback_to_any false

        # Invoke the user given block
        _ = unquote(block)

        # Finalize expansion
        unquote(after_defprotocol())
      end
    end
  end

  defp callback_ast_to_fa({_kind, {:"::", meta, [{name, _, args}, _return]}, _pos}) do
    [{{name, length(List.wrap(args))}, meta}]
  end

  defp callback_ast_to_fa(
         {_kind, {:when, _, [{:"::", meta, [{name, _, args}, _return]}, _vars]}, _pos}
       ) do
    [{{name, length(List.wrap(args))}, meta}]
  end

  defp callback_ast_to_fa({_kind, _clause, _pos}) do
    []
  end

  defp callback_metas(module, kind)
       when kind in [:callback, :macrocallback] do
    :lists.flatmap(&callback_ast_to_fa/1, Module.get_attribute(module, kind))
    |> :maps.from_list()
  end

  defp get_callback_line(fa, metas),
    do: :maps.get(fa, metas, [])[:line]

  defp warn(message, env, nil) do
    IO.warn(message, env)
  end

  defp warn(message, env, line) when is_integer(line) do
    IO.warn(message, %{env | line: line})
  end

  def __before_compile__(env) do
    functions = Module.get_attribute(env.module, :__functions__)

    if functions == [] do
      warn(
        "protocols must define at least one function, but none was defined",
        env,
        nil
      )
    end

    callback_metas = callback_metas(env.module, :callback)
    callbacks = :maps.keys(callback_metas)

    # TODO: Make an error on Elixir v2.0
    :lists.foreach(
      fn {name, arity} = fa ->
        warn(
          "cannot define @callback #{name}/#{arity} inside protocol, use def/1 to outline your protocol definition",
          env,
          get_callback_line(fa, callback_metas)
        )
      end,
      callbacks -- functions
    )

    # Macro Callbacks
    macrocallback_metas = callback_metas(env.module, :macrocallback)
    macrocallbacks = :maps.keys(macrocallback_metas)

    # TODO: Make an error on Elixir v2.0
    :lists.foreach(
      fn {name, arity} = fa ->
        warn(
          "cannot define @macrocallback #{name}/#{arity} inside protocol, use def/1 to outline your protocol definition",
          env,
          get_callback_line(fa, macrocallback_metas)
        )
      end,
      macrocallbacks
    )

    # Optional Callbacks
    optional_callbacks = Module.get_attribute(env.module, :optional_callbacks)

    if optional_callbacks != [] do
      warn(
        "cannot define @optional_callbacks inside protocol, all of the protocol definitions are required",
        env,
        nil
      )
    end
  end

  defp after_defprotocol do
    quote bind_quoted: [built_in: built_in()] do
      any_impl_for =
        if @fallback_to_any do
          __MODULE__.Any
        else
          nil
        end

      # Disable Dialyzer checks - before and after consolidation
      # the types could be more strict
      @dialyzer {:nowarn_function, __protocol__: 1, impl_for: 1, impl_for!: 1}

      @doc false
      @spec impl_for(term) :: atom | nil
      Kernel.def(impl_for(data))

      # Define the implementation for structs.
      #
      # It simply delegates to struct_impl_for which is then
      # optimized during protocol consolidation.
      Kernel.def impl_for(%struct{}) do
        struct_impl_for(struct)
      end

      # Define the implementation for built-ins
      :lists.foreach(
        fn {mod, guard} ->
          target = Protocol.__concat__(__MODULE__, mod)

          Kernel.def impl_for(data) when :erlang.unquote(guard)(data) do
            case Code.ensure_compiled(unquote(target)) do
              {:module, module} -> module
              {:error, _} -> unquote(any_impl_for)
            end
          end
        end,
        built_in
      )

      # Define a catch-all impl_for/1 clause to pacify Dialyzer (since
      # destructuring opaque types is illegal, Dialyzer will think none of the
      # previous clauses matches opaque types, and without this clause, will
      # conclude that impl_for can't handle an opaque argument). This is a hack
      # since it relies on Dialyzer not being smart enough to conclude that all
      # opaque types will get the any_impl_for/0 implementation.
      Kernel.def impl_for(_) do
        unquote(any_impl_for)
      end

      undefined_impl_description =
        Module.get_attribute(__MODULE__, :undefined_impl_description, "")

      @doc false
      @spec impl_for!(term) :: atom
      if any_impl_for do
        Kernel.def impl_for!(data) do
          impl_for(data)
        end
      else
        Kernel.def impl_for!(data) do
          impl_for(data) ||
            raise(Protocol.UndefinedError,
              protocol: __MODULE__,
              value: data,
              description: unquote(undefined_impl_description)
            )
        end
      end

      # Internal handler for Structs
      Kernel.defp struct_impl_for(struct) do
        case Code.ensure_compiled(Protocol.__concat__(__MODULE__, struct)) do
          {:module, module} -> module
          {:error, _} -> unquote(any_impl_for)
        end
      end

      # Inline struct implementation for performance
      @compile {:inline, struct_impl_for: 1}

      if not Module.defines_type?(__MODULE__, {:t, 0}) do
        @typedoc """
        All the types that implement this protocol.
        """
        @type t :: term
      end

      # Store information as an attribute so it
      # can be read without loading the module.
      Module.register_attribute(__MODULE__, :__protocol__, persist: true)
      @__protocol__ [fallback_to_any: !!@fallback_to_any]

      @doc false
      @spec __protocol__(:module) :: __MODULE__
      @spec __protocol__(:functions) :: [{atom(), arity()}]
      @spec __protocol__(:consolidated?) :: boolean()
      @spec __protocol__(:impls) :: :not_consolidated | {:consolidated, [module()]}
      Kernel.def(__protocol__(:module), do: __MODULE__)
      Kernel.def(__protocol__(:functions), do: unquote(:lists.sort(@__functions__)))
      Kernel.def(__protocol__(:consolidated?), do: false)
      Kernel.def(__protocol__(:impls), do: :not_consolidated)
    end
  end

  @doc false
  def __impl__(protocol, opts, do_block, env) do
    opts = Keyword.merge(opts, do_block)

    {for, opts} =
      Keyword.pop_lazy(opts, :for, fn ->
        env.module ||
          raise ArgumentError, "defimpl/3 expects a :for option when declared outside a module"
      end)

    expansion_env = %{env | module: env.module || Elixir, function: {:__impl__, 1}}
    protocol = Macro.expand_literals(protocol, expansion_env)
    for = Macro.expand_literals(for, expansion_env)

    case opts do
      [] -> raise ArgumentError, "defimpl expects a do-end block"
      [do: block] -> __impl__(protocol, for, block)
      _ -> raise ArgumentError, "unknown options given to defimpl, got: #{Macro.to_string(opts)}"
    end
  end

  defp __impl__(protocol, for, block) when is_list(for) do
    for f <- for, do: __impl__(protocol, f, block)
  end

  defp __impl__(protocol, for, block) do
    # Unquote the implementation just later
    # when all variables will already be injected
    # into the module body.
    impl =
      quote unquote: false do
        @doc false
        @spec __impl__(:for) :: unquote(for)
        @spec __impl__(:protocol) :: unquote(protocol)
        def __impl__(:for), do: unquote(for)
        def __impl__(:protocol), do: unquote(protocol)
      end

    # If the protocol is an atom, we will add an export dependency,
    # since it was expanded before-hand. Otherwise it is a dynamic
    # expression (and therefore most likely a compile-time one).
    behaviour =
      if is_atom(protocol) do
        quote(do: require(unquote(protocol)))
      else
        quote(do: protocol)
      end

    quote do
      protocol = unquote(protocol)
      for = unquote(for)
      name = Protocol.__concat__(protocol, for)

      Protocol.assert_protocol!(protocol)
      Protocol.__impl__!(protocol, for, __ENV__)

      defmodule name do
        @moduledoc false
        @behaviour unquote(behaviour)
        @protocol protocol
        @for for

        res = unquote(block)
        Module.register_attribute(__MODULE__, :__impl__, persist: true)
        @__impl__ [protocol: @protocol, for: @for]

        unquote(impl)
        res
      end
    end
  end

  @doc false
  def __derive__(derives, for, %Macro.Env{} = env) when is_atom(for) do
    foreach = fn
      proto when is_atom(proto) ->
        derive(proto, for, [], env)

      {proto, opts} when is_atom(proto) ->
        derive(proto, for, opts, env)
    end

    :lists.foreach(foreach, :lists.flatten(derives))

    :ok
  end

  defp derive(protocol, for, opts, env) do
    extra = ", cannot derive #{inspect(protocol)} for #{inspect(for)}"
    assert_protocol!(protocol, extra)

    {mod, args} =
      if macro_exported?(protocol, :__deriving__, 2) do
        {protocol, [for, opts]}
      else
        # TODO: Deprecate this on Elixir v1.22+
        assert_impl!(protocol, Any, extra)
        {__concat__(protocol, Any), [for, Macro.struct!(for, env), opts]}
      end

    # Clean up variables from eval context
    env = :elixir_env.reset_vars(env)

    :elixir_module.expand_callback(env.line, mod, :__deriving__, args, env, fn mod, fun, args ->
      if function_exported?(mod, fun, length(args)) do
        apply(mod, fun, args)
      else
        __impl__!(protocol, for, env)
        assert_impl!(protocol, Any, extra)
        impl = __concat__(protocol, Any)

        funs =
          for {fun, arity} <- protocol.__protocol__(:functions) do
            args = Macro.generate_arguments(arity, nil)

            quote do
              def unquote(fun)(unquote_splicing(args)),
                do: unquote(impl).unquote(fun)(unquote_splicing(args))
            end
          end

        quoted =
          quote do
            @behaviour unquote(protocol)
            Module.register_attribute(__MODULE__, :__impl__, persist: true)
            @__impl__ [protocol: unquote(protocol), for: unquote(for)]

            @doc false
            @spec __impl__(:protocol) :: unquote(protocol)
            @spec __impl__(:for) :: unquote(for)
            def __impl__(:protocol), do: unquote(protocol)
            def __impl__(:for), do: unquote(for)
          end

        Module.create(__concat__(protocol, for), [quoted | funs], Macro.Env.location(env))
      end
    end)
  end

  @doc false
  def __impl__!(protocol, for, env) do
    if not Code.get_compiler_option(:ignore_already_consolidated) and
         Protocol.consolidated?(protocol) do
      message =
        "the #{inspect(protocol)} protocol has already been consolidated, an " <>
          "implementation for #{inspect(for)} has no effect. If you want to " <>
          "implement protocols after compilation or during tests, check the " <>
          "\"Consolidation\" section in the Protocol module documentation"

      IO.warn(message, env)
    end

    # TODO: Make this an error on Elixir v2.0
    if for != Any and not Keyword.has_key?(built_in(), for) and for != env.module and
         for not in env.context_modules and Code.ensure_compiled(for) != {:module, for} do
      IO.warn(
        "you are implementing a protocol for #{inspect(for)} but said module is not available. " <>
          "Make sure the module name is correct. If #{inspect(for)} is an optional dependency, " <>
          "please wrap the protocol implementation in a Code.ensure_loaded?(#{inspect(for)}) check",
        env
      )
    end

    :ok
  end

  defp built_in do
    [
      {Tuple, :is_tuple},
      {Atom, :is_atom},
      {List, :is_list},
      {Map, :is_map},
      {BitString, :is_bitstring},
      {Integer, :is_integer},
      {Float, :is_float},
      {Function, :is_function},
      {PID, :is_pid},
      {Port, :is_port},
      {Reference, :is_reference}
    ]
  end

  @doc false
  def __concat__(left, right) do
    String.to_atom(
      ensure_prefix(Atom.to_string(left)) <> "." <> remove_prefix(Atom.to_string(right))
    )
  end

  defp ensure_prefix("Elixir." <> _ = left), do: left
  defp ensure_prefix(left), do: "Elixir." <> left

  defp remove_prefix("Elixir." <> right), do: right
  defp remove_prefix(right), do: right
end
