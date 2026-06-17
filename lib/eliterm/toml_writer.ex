defmodule Eliterm.TomlWriter do
  def encode(map) do
    # Top-level simple values first
    {simple, tables} = Enum.split_with(map, fn {_, v} -> not is_map(v) end)
    
    simple_str = Enum.map_join(simple, "\n", fn {k, v} -> "#{k} = #{encode_val(v)}" end)
    
    tables_str = encode_tables(tables, [])
    
    String.trim(simple_str <> "\n\n" <> tables_str) <> "\n"
  end

  defp encode_tables(tables, prefix) do
    Enum.map_join(tables, "\n\n", fn {k, v} ->
      new_prefix = prefix ++ [k]
      section_name = Enum.join(new_prefix, ".")
      
      {simple, sub_tables} = Enum.split_with(v, fn {_, sub_v} -> not is_map(sub_v) end)
      
      section_str = if simple != [] or sub_tables == [] do
        "[#{section_name}]\n" <> Enum.map_join(simple, "\n", fn {sk, sv} -> "#{sk} = #{encode_val(sv)}" end)
      else
        ""
      end
      
      sub_tables_str = if sub_tables != [] do
        (if section_str != "", do: section_str <> "\n\n", else: "") <> encode_tables(sub_tables, new_prefix)
      else
        section_str
      end
      
      sub_tables_str
    end)
  end

  defp encode_val(v) when is_binary(v), do: "\"#{v}\""
  defp encode_val(v) when is_integer(v), do: Integer.to_string(v)
  defp encode_val(v) when is_boolean(v), do: if(v, do: "true", else: "false")
  defp encode_val(v), do: "\"#{inspect(v)}\""
end
