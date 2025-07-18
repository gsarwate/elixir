# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

defmodule Mix.Tasks.Deps do
  use Mix.Task

  import Mix.Dep, only: [format_dep: 1, format_status: 1, check_lock: 1]

  @shortdoc "Lists dependencies and their status"

  @moduledoc ~S"""
  Lists all dependencies and their status.

  Dependencies must be specified in the `mix.exs` file in one of
  the following formats:

      {app, requirement}
      {app, opts}
      {app, requirement, opts}

  Where:

    * app is an atom
    * requirement is a `Version` requirement or a regular expression
    * opts is a keyword list of options

  For example:

      {:plug, ">= 0.4.0"}
      {:gettext, git: "https://github.com/elixir-lang/gettext.git", tag: "0.1"}
      {:local_dependency, path: "path/to/local_dependency"}

  By default, dependencies are fetched using the [Hex package manager](https://hex.pm/):

      {:plug, ">= 0.4.0"}

  By specifying such dependencies, Mix will automatically install
  Hex (if it wasn't previously installed) and download a package
  suitable to your project. Note Hex expects the dependency
  requirement to always be given and it will warn otherwise.

  Mix also supports Git and path dependencies:

      {:foobar, git: "https://github.com/elixir-lang/foobar.git", tag: "0.1"}
      {:foobar, path: "path/to/foobar"}

  And also in umbrella dependencies:

      {:my_app, in_umbrella: true}

  Path and in umbrella dependencies are automatically recompiled by
  the parent project whenever they change. While fetchable dependencies,
  like the ones using `:git`, are recompiled only when fetched/updated.

  The dependencies' versions are expected to be formatted according to
  Semantic Versioning and the requirements must be specified as defined
  in the `Version` module.

  ## Options

  Below we provide a more detailed look into the available options.

  ### Dependency definition options

    * `:app` - when set to `false`, does not read the app file for this
      dependency. By default, the app file is read

    * `:env` - the environment (as an atom) to run the dependency on.
      While your current project runs in `:dev` by default, dependencies
      defaults to `:prod` (except for `:in_umbrella` dependencies, see
      below)

    * `:compile` - a command (string) to compile the dependency; defaults to a `mix`,
      `rebar` or `make` command

    * `:optional` - marks the dependency as optional. In such cases, the
      current project will always include the optional dependency but any
      other project that depends on the current project won't be forced to
      use the optional dependency. However, if the other project includes
      the optional dependency on its own, the requirements and options
      specified here will also be applied. Optional dependencies will _not_
      be started by the application. You should consider compiling your
      projects with the `mix compile --no-optional-deps --warnings-as-errors`
      during test, to ensure your project compiles without warnings even
      if optional dependencies are missing

    * `:only` - the dependency is made available only in the given environments,
      useful when declaring dev- or test-only dependencies; by default the
      dependency will be available in all environments. The value of this option
      can either be a single environment (like `:dev`) or a list of environments
      (like `[:dev, :test]`). Keep in mind that your project runs in the `:dev`
      environment by default, however, all of your dependencies run in the `:prod`
      environment (unless the `:env` option above is given)

    * `:targets` - the dependency is made available only for the given targets.
      By default the dependency will be available in all targets. The value
      of this option can either be a single target (like `:host`) or a list of
      targets (like `[:host, :rpi3]`)

    * `:override` - if set to `true` the dependency will override any other
      definitions of itself by other dependencies

    * `:manager` - Mix can also compile Rebar3 and makefile projects
      and can fetch sub dependencies of Rebar3 projects. Mix will
      try to infer the type of project but it can be overridden with this
      option by setting it to `:mix`, `:rebar3`, or `:make`. In case
      there are conflicting definitions, the first manager in the list above
      will be picked up. For example, if a dependency is found with `:rebar3`
      as a manager in different part of the trees, `:rebar3` will be automatically
      picked. You can find the manager by running `mix deps` and override it by
      setting the `:override` option in a top-level project.

    * `:runtime` - whether the dependency is part of runtime applications.
      If the `:applications` key is not provided in `def application` in your
      `mix.exs` file, Mix will automatically include all dependencies as a runtime
      application, except if `runtime: false` is given. Defaults to `true`.

    * `:system_env` - an enumerable of key-value tuples of binaries to be set
      as environment variables when loading or compiling the dependency

  When a project is used as a dependency, it runs by default in the `:prod`
  environment. Therefore, if your project has dependencies that are only
  useful in development or testing, you want to specify those dependencies with
  the `:only` option above. You can also specify `:optional` dependencies
  in your project, which are not enforced upon users of your library, as outlined
  above. Finally, the [lockfile](`Mix.Project#module-configuration`) (usually
  named `mix.lock`) is ignored when a project is used as a dependency.

  ### Git options (`:git`)

    * `:git` - the Git repository URI
    * `:github` - a shortcut for specifying Git repos from GitHub, uses `:git`
    * `:ref` - the reference to checkout (may be a branch, a commit SHA or a tag)
    * `:branch` - the Git branch to checkout
    * `:tag` - the Git tag to checkout
    * `:submodules` - when `true`, initialize submodules for the repo
    * `:sparse` - checkout a single directory inside the Git repository and use it
      as your Mix dependency. Search "sparse Git checkouts" for more information.
    * `:subdir` *(since v1.13.0)* - search for the project in the given directory
      relative to the git checkout. This is similar to `:sparse` option but instead
      of a doing a sparse checkout it does a full checkout.
    * `:depth` *(since v1.17.0)* - creates a shallow clone of the Git repository,
      limiting the history to the specified number of commits. This can significantly
      improve clone speed for large repositories when full history is not needed.
      The value must be a positive integer, typically `1`. When using `:depth` with
      `:ref`, a fully spelled hex object name (a 40-character SHA-1 hash) is required.

  If your Git repository requires authentication, such as basic username:password
  HTTP authentication via URLs, it can be achieved via Git configuration, keeping
  the access rules outside of source control.

      $ git config --global url."https://YOUR_USER:YOUR_PASS@example.com/".insteadOf "https://example.com/"

  For more information, see the `git config` documentation:
  https://git-scm.com/docs/git-config#Documentation/git-config.txt-urlltbasegtinsteadOf

  ### Path options (`:path`)

    * `:path` - the path for the dependency
    * `:in_umbrella` - when `true`, sets a path dependency pointing to
      `"../#{app}"`, sharing the same environment as the current application

  ### Hex options (`:hex`)

    * `:hex` - the name of the package, which defaults to the application name
    * `:repo` - the repository to fetch the package from, used by remote or
      private repositories. Defaults to the global "hexpm" repository
    * `:warn_if_outdated` - warn if there is a more recent version of the package
      published on Hex.pm

  ## Deps task

  `mix deps` task lists all dependencies in the following format:

      APP VERSION (SCM) (MANAGER)
      [locked at REF]
      STATUS

  For dependencies satisfied by Hex, `REF` is the package checksum.

  For dependencies satisfied by git, `REF` is the commit object name,
  and may include branch or tag information.

  It supports the following options:

    * `--all` - lists all dependencies, regardless of specified environment

  """

  @impl true
  def run(args) do
    Mix.Project.get!()
    {opts, _, _} = OptionParser.parse(args, switches: [all: :boolean])
    loaded_opts = if opts[:all], do: [], else: [env: Mix.env(), target: Mix.target()]

    shell = Mix.shell()

    Mix.Dep.Converger.converge(loaded_opts)
    |> Enum.sort_by(& &1.app)
    |> Enum.each(fn dep ->
      %Mix.Dep{scm: scm, manager: manager} = dep
      dep = check_lock(dep)
      extra = if manager, do: " (#{manager})", else: ""

      shell.info("* #{format_dep(dep)}#{extra}")

      if formatted = scm.format_lock(dep.opts) do
        shell.info("  locked at #{formatted}")
      end

      shell.info("  #{format_status(dep)}")
    end)
  end
end
