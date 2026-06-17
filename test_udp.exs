defmodule UdpTest do
  def run do
    ports = [45892, 45893, 45894]
    tops = Enum.reduce(ports, [], fn port, acc ->
      case :gen_udp.open(port, [:binary, active: 10, reuseaddr: true]) do
        {:ok, socket} ->
          :gen_udp.close(socket)
          name = String.to_atom("eliterm_gossip_#{port}")
          [{name, [strategy: Cluster.Strategy.Gossip, config: [port: port]]} | acc]
        {:error, reason} ->
          IO.puts("Port #{port} unavailable: #{inspect(reason)}")
          acc
      end
    end)
    IO.inspect(tops)
  end
end
UdpTest.run()
