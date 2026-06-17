defmodule Eliterm.Config do
  @moduledoc """
  Manages saving and loading settings from eliterm.toml.
  """
  
  def path do
    Path.join([Eliterm.base_dir(), "eliterm.toml"])
  end

  def load do
    if File.exists?(path()) do
      case Toml.decode_file(path()) do
        {:ok, map} -> map
        _ -> %{}
      end
    else
      %{}
    end
  end

  def get(keys, default \\ nil) when is_list(keys) do
    get_in(load(), keys) || default
  end

  def put(keys, value) when is_list(keys) do
    config = load()
    new_config = put_in_nested(config, keys, value)
    save(new_config)
  end

  defp put_in_nested(map, [k], v), do: Map.put(map, k, v)
  defp put_in_nested(map, [h | t], v) do
    child = Map.get(map, h) |> Kernel.||(%{})
    Map.put(map, h, put_in_nested(child, t, v))
  end

  def save(map) do
    toml_str = Eliterm.TomlWriter.encode(map)
    File.mkdir_p!(Path.dirname(path()))
    File.write!(path(), toml_str)
  end
end
