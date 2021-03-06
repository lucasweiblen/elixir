defmodule Mix.CLI do
  @moduledoc false

  @doc """
  Runs Mix according to the command line arguments.
  """
  def main(args \\ System.argv) do
    Mix.Local.append_archives
    Mix.Local.append_paths

    case check_for_shortcuts(args) do
      :help ->
        proceed(["help"])
      :version ->
        display_version()
      nil ->
        proceed(args)
    end
  end

  defp proceed(args) do
    load_remote()
    args = load_mixfile(args)
    {task, args} = get_task(args)
    change_env(task)
    run_task(task, args)
  end

  @hex_requirement ">= 0.1.1-dev"

  defp load_remote do
    if Code.ensure_loaded?(Hex) do
      unless Version.match?(Hex.version, @hex_requirement) do
        update_hex()
      end

      try do
        Hex.start
      catch
        kind, reason ->
          stacktrace = System.stacktrace
          Mix.shell.error "Could not start Hex. Try fetching a new version with " <>
                          "`mix local.hex` or uninstalling it with `mix local.uninstall hex`"
          :erlang.raise(kind, reason, stacktrace)
      end
    end
  end

  defp update_hex do
    Mix.shell.info "Mix requires hex #{@hex_requirement} but you have #{Hex.version}"

    if Mix.shell.yes?("Shall I abort the current command and update hex?") do
      Mix.Tasks.Local.Hex.run ["--force"]
      exit(0)
    end
  end

  defp load_mixfile(args) do
    file = System.get_env("MIX_EXS") || "mix.exs"
    if File.regular?(file) do
      Code.load_file(file)
    end
    args
  end

  defp get_task(["-" <> _|_]) do
    Mix.shell.error "** (Mix) Cannot implicitly pass flags to default mix task, " <>
                    "please invoke instead: mix #{Mix.project[:default_task]}"
    exit(1)
  end

  defp get_task([h|t]) do
    {h, t}
  end

  defp get_task([]) do
    {Mix.project[:default_task], []}
  end

  defp run_task(name, args) do
    try do
      if Mix.Project.get do
        Mix.Task.run "deps.loadpaths", ["--no-deps-check"]
        Mix.Task.run "loadpaths", ["--no-elixir-version-check"]
        Mix.Task.reenable "deps.loadpaths"
        Mix.Task.reenable "loadpaths"
      end

      # If the task is not available, let's try to
      # compile the repository and then run it again.
      cond do
        Mix.Task.get(name) ->
          Mix.Task.run(name, args)
        Mix.Project.get ->
          Mix.Task.run("compile")
          Mix.Task.run(name, args)
        true ->
          # Raise no task error
          Mix.Task.get!(name)
      end
    rescue
      # We only rescue exceptions in the mix namespace, all
      # others pass through and will explode on the users face
      exception ->
        stacktrace = System.stacktrace

        if function_exported?(exception.__record__(:name), :mix_error, 1) do
          if msg = exception.message, do: Mix.shell.error "** (Mix) #{msg}"
          exit(1)
        else
          raise exception, [], stacktrace
        end
    end
  end

  defp change_env(task) do
    if nil?(System.get_env("MIX_ENV")) && (env = Mix.project[:preferred_cli_env][task]) do
      Mix.env(env)
      if project = Mix.Project.pop do
        {project, _config, file} = project
        Mix.Project.push project, file
      end
    end
  end

  defp display_version() do
    IO.puts "Elixir #{System.version}"
  end

  # Check for --help or --version in the args
  defp check_for_shortcuts([first_arg|_]) when first_arg in
      ["--help", "-h", "-help"], do: :help

  defp check_for_shortcuts([first_arg|_]) when first_arg in
      ["--version", "-v"], do: :version

  defp check_for_shortcuts(_), do: nil
end
