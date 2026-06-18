defmodule Eliterm.IOServer do
  @moduledoc """
  Erlang I/O プロトコルを部分的に実装し、
  プロセスの入出力を Unix ドメインソケットにリダイレクトする I/O デバイスサーバ。
  """
  use GenServer

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  @impl true
  def init(socket) do
    {:ok, socket}
  end

  @impl true
  def handle_info({:io_request, from, reply_as, req}, socket) do
    reply = handle_io(req, socket)
    send(from, {:io_reply, reply_as, reply})
    {:noreply, socket}
  end

  defp handle_io({:put_chars, _encoding, chars}, socket) do
    :gen_tcp.send(socket, chars)
    :ok
  end

  defp handle_io({:put_chars, chars}, socket) do
    :gen_tcp.send(socket, chars)
    :ok
  end

  defp handle_io({:get_line, _encoding, _prompt}, socket) do
    read_line(socket)
  end

  defp handle_io({:get_line, _prompt}, socket) do
    read_line(socket)
  end

  defp handle_io(_req, _socket) do
    {:error, :request}
  end

  defp read_line(socket) do
    # 行単位で読み込むために一時的にパケットモードを :line にする
    :inet.setopts(socket, [packet: :line])
    res = case :gen_tcp.recv(socket, 0) do
      {:ok, line} -> line
      {:error, _} -> :eof
    end
    # パケットモードを raw に戻す
    :inet.setopts(socket, [packet: :raw])
    res
  end
end
