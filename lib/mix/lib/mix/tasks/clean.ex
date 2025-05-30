# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

defmodule Mix.Tasks.Clean do
  use Mix.Task

  @shortdoc "Deletes generated application files"
  @recursive true

  @moduledoc """
  Deletes generated application files.

  This command deletes all build artifacts for the current project.
  Dependencies' sources and build files are cleaned only if the
  `--deps` option is given.

  By default this task works across all environments, unless `--only`
  is given.

  ## Command line options

    * `--deps` - clean dependencies as well as the current project's files
    * `--only` - only clean the given environment

  """

  @switches [deps: :boolean, only: :string]

  @impl true
  def run(args) do
    Mix.Project.get!()
    loadpaths!()

    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    Mix.Project.with_build_lock(fn ->
      do_run(opts)
    end)
  end

  defp do_run(opts) do
    # First, we get the tasks. After that, we clean them.
    # This is to avoid a task cleaning a compiler module.
    tasks =
      for compiler <- Mix.Task.Compiler.compilers(),
          module = Mix.Task.get("compile.#{compiler}"),
          function_exported?(module, :clean, 0),
          do: module

    Mix.Compilers.Protocol.clean()
    Enum.each(tasks, & &1.clean())

    build =
      Mix.Project.build_path()
      |> Path.dirname()
      |> Path.join("*#{opts[:only]}")

    if opts[:deps] do
      build
      |> Path.wildcard()
      |> Enum.each(&File.rm_rf/1)
    else
      build
      |> Path.join("lib/#{Mix.Project.config()[:app]}")
      |> Path.wildcard()
      |> Enum.each(&File.rm_rf/1)
    end
  end

  # Loadpaths without checks because compilers may be defined in deps.
  defp loadpaths! do
    options = [
      "--no-elixir-version-check",
      "--no-deps-check",
      "--no-archives-check",
      "--no-listeners"
    ]

    Mix.Task.run("loadpaths", options)
    Mix.Task.reenable("loadpaths")
    Mix.Task.reenable("deps.loadpaths")
  end
end
