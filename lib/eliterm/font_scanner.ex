defmodule Eliterm.FontScanner do
  @known_fonts [
    {"Fira Code", ["FiraCode", "Fira Code"]},
    {"Cascadia Code", ["CascadiaCode", "Cascadia Code"]},
    {"Source Code Pro", ["SourceCodePro", "Source Code Pro"]},
    {"Hack", ["Hack"]},
    {"JetBrains Mono", ["JetBrainsMono", "JetBrains Mono"]},
    {"Ubuntu Mono", ["UbuntuMono", "Ubuntu Mono"]}
  ]

  @doc """
  Scans the system for known developer fonts and returns a list of installed font families.
  """
  def scan do
    font_files = get_font_files(:os.type())
    
    Enum.reduce(@known_fonts, [], fn {family, patterns}, acc ->
      found = Enum.any?(font_files, fn file ->
        Enum.any?(patterns, fn pattern ->
          String.contains?(String.downcase(file), String.downcase(pattern))
        end)
      end)
      
      if found do
        [family | acc]
      else
        acc
      end
    end) |> Enum.reverse()
  end

  defp get_font_files({:unix, :darwin}) do
    dirs = [
      "/System/Library/Fonts",
      "/Library/Fonts",
      Path.expand("~/Library/Fonts")
    ]
    
    Enum.flat_map(dirs, fn dir ->
      case File.ls(dir) do
        {:ok, files} -> files
        _ -> []
      end
    end)
  end

  defp get_font_files({:win32, :nt}) do
    # Global font directory
    dir = "C:\\Windows\\Fonts"
    files = case File.ls(dir) do
      {:ok, files} -> files
      _ -> []
    end
    
    # User font directory (Windows 10/11)
    user_dir = Path.join([System.user_home!(), "AppData", "Local", "Microsoft", "Windows", "Fonts"])
    user_files = case File.ls(user_dir) do
      {:ok, files} -> files
      _ -> []
    end

    files ++ user_files
  end

  defp get_font_files(_) do
    []
  end
end
